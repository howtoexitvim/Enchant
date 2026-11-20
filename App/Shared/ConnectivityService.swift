import Foundation
import Combine
import CryptoKit
import WatchConnectivity

@MainActor final class ConnectivityService: NSObject, ObservableObject, WCSessionDelegate {
    @Published var status = L10n.text("等待配对设备")
    // True means durably handled, including permanent format rejection. False keeps the inbox for retry.
    var onReceive: ((Data) -> Bool)?
    var onReady: (() -> Void)?
    var onPreferences: ((Data) -> Void)?
    private var lastSnapshotDigest: String?
    private var lastHandledDigest: String?
    private var volatileInbox: [String: Data] = [:]
    private var retryTask: Task<Void, Never>?
    private var retryAttempt = 0
    private let retryDelays: [TimeInterval]
    private let enabled: Bool
    nonisolated private let directory: URL

    init(enabled: Bool = true, directory: URL? = nil, retryDelays: [TimeInterval] = [2, 5, 15, 30, 60]) {
        self.enabled = enabled
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Enchant/Sync", isDirectory: true)
        self.retryDelays = retryDelays
        super.init()
        if enabled && WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }

    deinit { retryTask?.cancel() }

    func send(_ data: Data) {
        guard let session = readySession() else { return }
        let digest = Self.digest(data)
        guard lastSnapshotDigest != digest else { return }
        if session.outstandingFileTransfers.contains(where: { $0.file.metadata?["archiveSHA256"] as? String == digest }) {
            lastSnapshotDigest = digest; status = L10n.text("正在传送至配对设备"); return
        }
        do {
            let outbox = directory.appendingPathComponent("Outbox", isDirectory: true)
            try Self.prepareDirectory(directory); try Self.prepareDirectory(outbox)
            let url = outbox.appendingPathComponent("\(digest).json")
            try Self.write(data, to: url)
            session.transferFile(url, metadata: ["enchantArchive": 1, "archiveSHA256": digest])
            lastSnapshotDigest = digest; lastHandledDigest = nil
            status = L10n.text("正在传送至配对设备")
        } catch {
            status = L10n.format("本机已保存 · 同步准备失败：%@", error.localizedDescription); scheduleRetry()
        }
    }

    func sendPreferences(_ data: Data) {
        guard let session = readySession() else { return }
        do { try session.updateApplicationContext(["preferences": data]) }
        catch { status = L10n.format("设置同步待重试：%@", error.localizedDescription); scheduleRetry() }
    }

    // AppModel installs all callbacks before refresh, so persisted data is never silently consumed at startup.
    func refresh() {
        retryTask?.cancel(); retryTask = nil; retryAttempt = 0
        retryPending()
    }

    private func retryPending() {
        lastSnapshotDigest = nil
        replayInbox()
        if enabled && WCSession.isSupported(), WCSession.default.activationState != .activated { WCSession.default.activate() }
        onReady?()
    }

    private func scheduleRetry() {
        guard retryTask == nil, retryAttempt < retryDelays.count else { return }
        let delay = retryDelays[retryAttempt]; retryAttempt += 1
        retryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.retryTask = nil; self.retryPending()
        }
    }

    private func readySession() -> WCSession? {
        guard enabled, WCSession.isSupported() else { return nil }
        let session = WCSession.default
        guard session.activationState == .activated else { status = L10n.text("本机已保存 · 等待配对设备"); return nil }
        #if os(iOS)
        guard session.isPaired && session.isWatchAppInstalled else { status = L10n.text("本机已保存 · 请安装 Watch App"); return nil }
        #else
        guard session.isCompanionAppInstalled else { status = L10n.text("本机已保存 · 请安装 iPhone App"); return nil }
        #endif
        return session
    }

    @discardableResult nonisolated func receiveArchive(_ data: Data) -> Task<Void, Never> {
        // Staging is synchronous: WCSession removes its incoming file as soon as the delegate returns.
        let persisted = Result { try Self.persistIncoming(data, directory: directory) }
        return Task { @MainActor [weak self] in
            guard let self else { return }
            self.handleIncoming(data, persisted: persisted)
        }
    }

    private func handleIncoming(_ data: Data, persisted: Result<URL, Error>) {
        let digest = Self.digest(data)
        var needsResend = false
        switch persisted {
        case .success: volatileInbox.removeValue(forKey: digest)
        case .failure(let error):
            // If the inbox cannot be written (for example, full disk), retain bytes while alive and
            // ask the sender to queue a fresh full archive in WCSession's persistent transport.
            volatileInbox[digest] = data
            status = L10n.format("配对数据待保存：%@", error.localizedDescription)
            needsResend = true
        }
        guard let onReceive else {
            if needsResend { requestResend(digest: digest) }; scheduleRetry(); return
        }
        guard onReceive(data) else {
            if needsResend { requestResend(digest: digest) }
            status = L10n.text("配对数据待保存 · 将重试"); scheduleRetry(); return
        }
        guard acknowledge(digest: digest) else { scheduleRetry(); return }
        volatileInbox.removeValue(forKey: digest)
        if case .success(let url) = persisted {
            do { if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) } }
            catch { status = L10n.text("配对数据已处理 · 收件清理待重试"); scheduleRetry() }
        }
    }

    private func replayInbox() {
        let inbox = directory.appendingPathComponent("Inbox", isDirectory: true)
        var processed: Set<String> = []
        do {
            if FileManager.default.fileExists(atPath: inbox.path) {
                let files = try FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                for url in files {
                    do {
                        let data = try Data(contentsOf: url); processed.insert(Self.digest(data))
                        handleIncoming(data, persisted: .success(url))
                    } catch {
                        status = L10n.format("读取配对收件失败：%@", error.localizedDescription)
                        requestResend(digest: url.deletingPathExtension().lastPathComponent); scheduleRetry()
                    }
                }
            }
        } catch { status = L10n.format("配对收件待重试：%@", error.localizedDescription); scheduleRetry() }
        let pendingBytes = volatileInbox
        for (digest, data) in pendingBytes where !processed.contains(digest) {
            handleIncoming(data, persisted: Result { try Self.persistIncoming(data, directory: directory) })
        }
    }

    private func acknowledge(digest: String) -> Bool {
        guard enabled else { return true }
        guard let session = readySession() else { return false }
        if !session.outstandingUserInfoTransfers.contains(where: { $0.userInfo["enchantHandled"] as? Int == 1 && $0.userInfo["archiveSHA256"] as? String == digest }) {
            session.transferUserInfo(["enchantHandled": 1, "archiveSHA256": digest])
        }
        return true
    }

    private func requestResend(digest: String?) {
        guard let session = readySession() else { return }
        if session.outstandingUserInfoTransfers.contains(where: { $0.userInfo["enchantRetry"] as? Int == 1 && $0.userInfo["archiveSHA256"] as? String == digest }) { return }
        var request: [String: Any] = ["enchantRetry": 1]
        if let digest { request["archiveSHA256"] = digest }
        session.transferUserInfo(request)
    }

    func transferFinished(error: Error?, digest: String? = nil) {
        guard digest == nil || digest == lastSnapshotDigest else { return }
        if let error {
            lastSnapshotDigest = nil
            status = L10n.format("本机保存 · 同步待重试：%@", error.localizedDescription); scheduleRetry()
        } else if digest != nil && digest == lastHandledDigest { status = L10n.text("配对传输完成") }
        else { status = L10n.text("已传送 · 等待对端处理") }
    }

    nonisolated private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func prepareDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        #if os(iOS) || os(watchOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
        var mutableURL = url; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }

    nonisolated private static func write(_ data: Data, to url: URL) throws {
        #if os(iOS) || os(watchOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    nonisolated private static func persistIncoming(_ data: Data, directory: URL) throws -> URL {
        let inbox = directory.appendingPathComponent("Inbox", isDirectory: true)
        try prepareDirectory(directory); try prepareDirectory(inbox)
        let url = inbox.appendingPathComponent("\(digest(data)).json")
        if (try? Data(contentsOf: url)) != data { try write(data, to: url) }
        return url
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["preferences"] as? Data else { return }
        Task { @MainActor in self.onPreferences?(data) }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error { self.status = L10n.format("同步未启动：%@", error.localizedDescription); self.scheduleRetry() }
            else if activationState == .activated { self.status = L10n.text("配对同步已就绪"); self.refresh() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?["enchantArchive"] as? Int == 1 else { return }
        do { receiveArchive(try Data(contentsOf: file.fileURL)) }
        catch {
            let digest = file.metadata?["archiveSHA256"] as? String
            Task { @MainActor in
                self.status = L10n.format("读取同步文件失败：%@", error.localizedDescription)
                self.requestResend(digest: digest); self.scheduleRetry()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard fileTransfer.file.metadata?["enchantArchive"] as? Int == 1 else { return }
        let digest = fileTransfer.file.metadata?["archiveSHA256"] as? String
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        Task { @MainActor in self.transferFinished(error: error, digest: digest) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let digest = userInfo["archiveSHA256"] as? String
        let handled = userInfo["enchantHandled"] as? Int == 1, retry = userInfo["enchantRetry"] as? Int == 1
        Task { @MainActor in
            if handled, let digest, digest == self.lastSnapshotDigest {
                self.lastHandledDigest = digest; self.status = L10n.text("配对传输完成")
            }
            if retry { self.lastSnapshotDigest = nil; self.scheduleRetry() }
        }
    }

    #if os(iOS)
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) { Task { @MainActor in self.refresh() } }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
