import SwiftUI
import WatchKit

private let workoutRecoveryRequested = Notification.Name("EnchantWorkoutRecoveryRequested")
final class EnchantWatchDelegate: NSObject, WKApplicationDelegate {
    func handleActiveWorkoutRecovery() {
        NotificationCenter.default.post(name: workoutRecoveryRequested, object: nil)
    }
}
@main struct EnchantWatchApp: App {
    @WKApplicationDelegateAdaptor(EnchantWatchDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    var body: some Scene { WindowGroup { WatchRoot().environmentObject(model).preferredColorScheme(.dark).tint(EnchantTheme.accent).font(EnchantTheme.body(14)) } }
}
struct WatchRoot: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) var phase
    var body: some View {
        NavigationStack {
            WatchCanvas { height in
                Group {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-preview-detail"), let record = model.visibleRecords.first { WatchDetail(recordID: record.id) }
                    else if ProcessInfo.processInfo.arguments.contains("-preview-settings") { WatchSettings() }
                    else if ProcessInfo.processInfo.arguments.contains("-preview-journal") { WatchJournal() }
                    else if ProcessInfo.processInfo.arguments.contains("-preview-trash") { WatchTrash() }
                    else if ProcessInfo.processInfo.arguments.contains("-preview-note"), let record = model.visibleRecords.first { WatchNoteEditor(recordID: record.id) }
                    else if ProcessInfo.processInfo.arguments.contains("-preview-session"), let record = model.visibleRecords.first { WatchSession(record: record) }
                    else if ProcessInfo.processInfo.arguments.contains("-preview-result"), let record = model.visibleRecords.first { WatchResult(record: record) }
                    else { mainContent(height: height) }
                    #else
                    mainContent(height: height)
                    #endif
                }
            }
        }.ignoresSafeArea(.container).background(EnchantTheme.background).onChange(of: phase) { _, value in model.sceneChanged(value) }.onAppear { model.sceneChanged(phase) }
        .onReceive(NotificationCenter.default.publisher(for: workoutRecoveryRequested)) { _ in model.recoverHealthSession() }
        .alert("操作未完成", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("知道了") { model.errorMessage = nil } } message: { Text(model.errorMessage ?? "") }
    }
    @ViewBuilder private func mainContent(height: CGFloat) -> some View {
        if let message = model.loadError {
            VStack(spacing: 6) {
                Illustration(name: "Journal", size: 32)
                Text("资料库读取失败").font(EnchantTheme.body(16))
                Text(message).font(EnchantTheme.body(12)).lineLimit(height < 210 ? 3 : 4).multilineTextAlignment(.center)
                Text("保留原文件，再建空资料库").font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted).multilineTextAlignment(.center)
                Button("保留并重建") { model.createFreshStorePreservingOriginal() }
                    .buttonStyle(EnchantButton(fontSize: 16)).frame(height: 44)
            }.padding(.horizontal, 8)
        }
        else if let result = model.result { WatchResult(record: result) }
        else if let record = model.active { if record.phase == .finished { WatchResult(record: record) } else { WatchSession(record: record) } }
        else { WatchHome(height: height) }
    }

}
// Reserve the system clock once; pushed pages use the same full-screen canvas.
private struct WatchCanvas<Content: View>: View {
    @ViewBuilder let content: (CGFloat) -> Content
    var body: some View {
        GeometryReader { geometry in
            let height = max(0, geometry.size.height - 25)
            content(height).environment(\.watchControlScale, max(0.78, min(1, geometry.size.width / 208)))
                .frame(width: geometry.size.width, height: height).padding(.top, 22).padding(.bottom, 3)
        }.ignoresSafeArea(.container).background(EnchantTheme.background).toolbar(.hidden, for: .navigationBar)
    }
}
struct WatchHome: View {
    @EnvironmentObject var model: AppModel
    let height: CGFloat
    var body: some View {
        VStack(spacing: 8) {
            Illustration(name: "PlainSword", size: min(78, height * 0.38))
            Button { model.start() } label: { Text("附魔开始") }.buttonStyle(EnchantButton()).accessibilityLabel("附魔开始").accessibilityIdentifier("start-enchantment")
            HStack(spacing: 8) {
                NavigationLink { WatchCanvas { _ in WatchJournal() } } label: { HStack(spacing: 5) { Illustration(name: "Journal", size: 24); Text("手账").lineLimit(1).minimumScaleFactor(0.75) } }.buttonStyle(.plain).frame(maxWidth: .infinity, minHeight: 44).accessibilityLabel("手账")
                NavigationLink { WatchCanvas { _ in WatchSettings() } } label: { HStack(spacing: 5) { PixelIcon(name: "settings", size: 20); Text("设置").lineLimit(1).minimumScaleFactor(0.75) } }.buttonStyle(.plain).frame(maxWidth: .infinity, minHeight: 44).accessibilityLabel("设置")
            }
        }.padding(.horizontal, 8)
    }
}
private func watchMetric(_ value: String, _ label: String, icon: String) -> some View {
    VStack(spacing: 3) { HStack(spacing: 4) { PixelIcon(name: icon, size: 12); Text(value).font(EnchantTheme.digits(16)).lineLimit(1).minimumScaleFactor(0.6) }.frame(height: 20); Text(L10n.text(label)).font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted).lineLimit(1).minimumScaleFactor(0.8).frame(height: 16) }.frame(maxWidth: .infinity)
}
private func heartValue(_ value: Double?) -> String { value.map { String(Int($0.rounded())) } ?? "--" }
struct WatchSession: View {
    @EnvironmentObject var model: AppModel
    let record: SessionRecord
    @State private var discarding = false
    var body: some View {
        TabView {
            VStack(spacing: 2) {
                Text(model.idleCountdown.map { L10n.format("%ld秒后结束", $0) } ?? L10n.text(record.phase == .recording ? "正在附魔" : record.phase == .paused ? "已暂停" : "中断记录")).font(EnchantTheme.title(20)).foregroundStyle(model.idleCountdown == nil ? EnchantTheme.magic : EnchantTheme.gold).lineLimit(1).frame(height: 24)
                Text(SessionRecord.durationString(record.activeDuration(at: model.now))).font(EnchantTheme.digits(28)).lineLimit(1).minimumScaleFactor(0.6).frame(height: 34)
                HStack { watchMetric(heartValue(model.currentHeartRate(for: record)), "心率 bpm", icon: "heart"); watchMetric(record.cycleEstimate.map(String.init) ?? "--", "次数 · 估算", icon: "sword") }
                HStack(spacing: 8) {
                    Button(L10n.text(model.idleCountdown != nil ? "继续" : record.phase == .recording ? "暂停" : "继续")) { if model.idleCountdown != nil { model.continueAfterIdle() } else if record.phase == .recording { model.pause() } else { model.resume() } }.buttonStyle(EnchantButton(secondary: true))
                    Button("结束") { model.finish() }.buttonStyle(EnchantButton()).accessibilityLabel("结束附魔")
                }
            }.padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 18)
            VStack(spacing: 8) {
                HeartChart(record: record, compact: true)
                Button("丢弃记录", role: .destructive) { discarding = true }.buttonStyle(.plain).frame(minHeight: 44)
            }.padding(.horizontal, 8).padding(.bottom, 18)
        }.tabViewStyle(.page(indexDisplayMode: .always))
        .confirmationDialog("丢弃本次记录？", isPresented: $discarding) { Button("丢弃", role: .destructive) { model.discardActive() } }
    }
}
struct WatchResult: View {
    @EnvironmentObject var model: AppModel
    let record: SessionRecord
    var body: some View {
        VStack(spacing: 4) {
            Illustration(name: "Sword", size: 32)
            Text("附魔完成").font(EnchantTheme.title(20)).foregroundStyle(EnchantTheme.gold)
            Text(record.formattedDuration).font(EnchantTheme.digits(28)).lineLimit(1).minimumScaleFactor(0.65)
            Text(L10n.format("平均 %@ bpm · %@次估算", heartValue(record.averageHeartRate), record.cycleEstimate.map(String.init) ?? "--")).font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted).lineLimit(1).minimumScaleFactor(0.7)
            if model.engine != nil { Button("重试保存") { model.saveFinished() }.buttonStyle(EnchantButton()) }
            else {
                HStack(spacing: 6) {
                    NavigationLink("备注") { WatchCanvas { _ in WatchNoteEditor(recordID: record.id) } }.buttonStyle(EnchantButton(secondary: true, fontSize: 16))
                    Button("完成") { model.closeResult() }.buttonStyle(EnchantButton())
                }
            }
        }.padding(.horizontal, 8)
    }
}
struct WatchJournal: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var search = ""
    private var filtered: [SessionRecord] { search.isEmpty ? model.visibleRecords : model.visibleRecords.filter { ($0.dayKey + " " + $0.journalText).localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(spacing: 0) {
            TextField("搜索日期或备注", text: $search).font(EnchantTheme.body(12)).padding(.horizontal, 8).frame(minHeight: 32).accessibilityLabel("搜索记录")
            Text(monthSummary).font(EnchantTheme.body(10)).foregroundStyle(EnchantTheme.muted).lineLimit(1).minimumScaleFactor(0.75)
            List {
                if filtered.isEmpty { VStack(spacing: 8) { Illustration(name: "Journal", size: 44); Text(L10n.text(search.isEmpty ? "这页还空着" : "没有匹配记录")); Text(L10n.text(search.isEmpty ? "开始后自动收藏" : "换个词再试试")).font(EnchantTheme.body(12)) } }
                ForEach(filtered) { record in NavigationLink { WatchCanvas { _ in WatchDetail(recordID: record.id) } } label: { HStack(spacing: 6) { Illustration(name: "Journal", size: 24); VStack(alignment: .leading, spacing: 4) { Text(record.dayKey).font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted); Text(record.formattedDuration).font(EnchantTheme.digits(18)).foregroundStyle(EnchantTheme.accent); Text(record.note.isEmpty ? L10n.format("%@记录", record.originLabel) : record.note).font(EnchantTheme.body(12)).lineLimit(1) } } } }
            }.scrollIndicators(.hidden)
            Button("返回") { dismiss() }.buttonStyle(.plain).frame(maxWidth: .infinity, minHeight: 32).font(EnchantTheme.body(12))
        }.navigationTitle("魔法手账").toolbar(.hidden, for: .navigationBar)
    }
    private var monthSummary: String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM"; let prefix = f.string(from: Date())
        let records = model.visibleRecords.filter { $0.dayKey.hasPrefix(prefix) }
        return L10n.format("本月 %ld 条 · %@", records.count, SessionRecord.durationString(records.reduce(0) { $0 + $1.activeDuration(at: $1.endedAt ?? $1.lastCheckpoint) }))
    }

}
struct WatchDetail: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let recordID: UUID
    @State private var deleting = false
    @State private var page = previewPage()
    var body: some View {
        if let record = model.visibleRecords.first(where: { $0.id == recordID }) {
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    VStack(spacing: 4) {
                        Text(record.dayKey).font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted).frame(height: 16)
                        Text(record.formattedDuration).font(EnchantTheme.digits(28)).lineLimit(1).minimumScaleFactor(0.65).foregroundStyle(EnchantTheme.accent).frame(height: 32)
                        HStack { watchMetric(heartValue(record.averageHeartRate), "平均 bpm", icon: "heart"); watchMetric(heartValue(record.peakHeartRate), "峰值 bpm", icon: "heart") }
                        // Keep the estimate and origin together on narrow displays.
                        Text(L10n.format("%@次估算 · %@", record.cycleEstimate.map(String.init) ?? "--", record.originLabel)).font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted).lineLimit(1).minimumScaleFactor(0.75).frame(height: 16)
                    }.padding(.horizontal, 8).padding(.bottom, 18).tag(0)
                    HeartChart(record: record, compact: true, height: 68).padding(.horizontal, 8).padding(.bottom, 18).tag(1)
                    VStack(spacing: 4) {
                        ScrollView { JournalNoteText(text: record.journalText.isEmpty ? L10n.text("还没有备注") : record.journalText).font(EnchantTheme.body(12)).frame(maxWidth: .infinity, alignment: .leading) }.scrollIndicators(.hidden)
                        NavigationLink("编辑备注") { WatchCanvas { _ in WatchNoteEditor(recordID: recordID) } }.buttonStyle(EnchantButton(secondary: true))
                        Button("删除记录", role: .destructive) { deleting = true }.buttonStyle(.plain).frame(minHeight: 32).font(EnchantTheme.body(14))
                    }.padding(.horizontal, 8).padding(.bottom, 18).tag(2)

                }.tabViewStyle(.page(indexDisplayMode: .always))
                Button("返回手账") { dismiss() }.buttonStyle(.plain).frame(maxWidth: .infinity, minHeight: 32).font(EnchantTheme.body(12))
            }.toolbar(.hidden, for: .navigationBar).task { await model.loadHearts(for: record) }
            .confirmationDialog("移到回收站？", isPresented: $deleting) { Button("删除", role: .destructive) { if model.delete(recordID) { dismiss() } } }
        } else {
            VStack(spacing: 12) {
                Illustration(name: "Journal", size: 40)
                Text("记录已移到回收站").font(EnchantTheme.body(14)).multilineTextAlignment(.center)
                Button("返回手账") { dismiss() }.buttonStyle(EnchantButton(secondary: true))
            }.padding(.horizontal, 8)
        }
    }
}
struct WatchNoteEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let recordID: UUID
    @State private var note = ""
    @State private var loaded = false
    var body: some View {
        VStack(spacing: 8) { Illustration(name: "Journal", size: 32); TextField("写下备注…", text: $note); Button("保存备注") { guard var record = model.visibleRecords.first(where: { $0.id == recordID }) else { model.errorMessage = L10n.text("记录已被删除，草稿已保留。"); return }; record.note = note; record.links = RecordLink.detected(in: note); if model.save(record) { model.removeDraft(key: recordID.uuidString); dismiss() } }.buttonStyle(EnchantButton()); Button("取消") { dismiss() }.buttonStyle(.plain).frame(minHeight: 32).font(EnchantTheme.body(14)) }.padding(.horizontal, 8).toolbar(.hidden, for: .navigationBar).onAppear { if !loaded { note = model.visibleRecords.first { $0.id == recordID }?.journalText ?? ""; if let data = model.readDraft(key: recordID.uuidString), let cached = try? JSONDecoder().decode([String: String].self, from: data) { note = cached["note"] ?? note }; loaded = true } }
        .onChange(of: note) { _, value in if loaded, let data = try? JSONEncoder().encode(["note": value]) { model.writeDraft(data, key: recordID.uuidString) } }
    }
}
struct WatchSettings: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.watchControlScale) private var controlScale
    private var compact: Bool { controlScale <= 190.0 / 208.0 }
    private var faceHeight: CGFloat { compact ? (controlScale <= 170.0 / 208.0 ? 38 : 40) : 44 }
    private var iconSize: CGFloat { compact ? 12 : 16 }
    private var cornerRadius: CGFloat { compact ? 8 : 10 }
    var body: some View {
        VStack(spacing: 4) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: compact ? 2 : 4) {
                preference("自动开始", icon: "play", value: $model.preferences.automaticStart)
                preference("静止提醒", icon: "pause", value: $model.preferences.autoStop)
                preference("记录心率", icon: "heart", value: $model.preferences.healthEnabled)
                preference("声音", icon: "sound", value: $model.preferences.sound)
                preference("触感", icon: "haptics", value: $model.preferences.haptics)
                NavigationLink { WatchCanvas { _ in WatchTrash() } } label: {
                    VStack(spacing: 2) {
                        PixelIcon(name: "trash", size: compact ? 12 : 18)
                        Text("回收站").font(EnchantTheme.body(12)).lineLimit(1).minimumScaleFactor(0.85)
                    }.frame(maxWidth: .infinity).frame(height: faceHeight)
                        .background(EnchantTheme.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
                        .padding(.horizontal, compact ? 2 : 0).frame(height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("回收站")
            }
            Button("返回") { dismiss() }.buttonStyle(.plain).frame(maxWidth: .infinity, minHeight: 28).font(EnchantTheme.body(14))
        }.padding(.horizontal, 8).toolbar(.hidden, for: .navigationBar)
    }
    private func preference(_ title: String, icon: String, value: Binding<Bool>) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            VStack(spacing: 2) {
                PixelIcon(name: icon, color: value.wrappedValue ? EnchantTheme.accent : EnchantTheme.muted, size: iconSize).opacity(value.wrappedValue ? 1 : 0.6)
                Text(L10n.text(title)).font(EnchantTheme.body(12)).foregroundStyle(value.wrappedValue ? EnchantTheme.ink : EnchantTheme.muted).lineLimit(1).minimumScaleFactor(0.85)
            }.frame(maxWidth: .infinity).frame(height: faceHeight)
                .background(value.wrappedValue ? EnchantTheme.accent.opacity(0.13) : EnchantTheme.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(value.wrappedValue ? EnchantTheme.accent.opacity(0.8) : EnchantTheme.border.opacity(0.4)))
                // Compact faces leave room below the clock; every control keeps its 44pt touch slot.
                .padding(.horizontal, compact ? 2 : 0).frame(height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(L10n.text(title)).accessibilityValue(L10n.text(value.wrappedValue ? "已开启" : "已关闭"))
    }
}
struct WatchTrash: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(spacing: 0) {
            if model.deletedRecords.isEmpty {
                VStack(spacing: 8) { PixelIcon(name: "trash", size: 54); Text("回收站为空").font(EnchantTheme.title(20)); Text("已删除记录可恢复").font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List { ForEach(model.deletedRecords) { record in VStack(alignment: .leading, spacing: 6) { HStack { Illustration(name: "Journal", size: 22); Text(record.dayKey).font(EnchantTheme.body(12)) }; Text(record.formattedDuration).font(EnchantTheme.digits(18)); Button("恢复") { model.restore(record.id) }.frame(minHeight: 44) } } }.scrollIndicators(.hidden)
            }
            Button("返回") { dismiss() }.buttonStyle(.plain).frame(minHeight: 32).font(EnchantTheme.body(14))
        }.toolbar(.hidden, for: .navigationBar)
    }
}

private func previewPage() -> Int {
    #if DEBUG
    let value = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("-preview-page=") }.flatMap { Int($0.dropFirst("-preview-page=".count)) } ?? 0
    return min(2, max(0, value))
    #else
    return 0
    #endif
}
