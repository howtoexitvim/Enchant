import XCTest
@testable import Enchant

@MainActor final class ConnectivityServiceTests: XCTestCase {
    private let archive = Data("{\"schemaVersion\":1,\"records\":[]}".utf8)

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("enchant.sync-tests.\(UUID().uuidString)")
    }

    private func storedArchives(in directory: URL) -> [URL] {
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        return (files?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "json" }
    }

    func testFailedReceiverKeepsArchiveUntilSuccessfulRefresh() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let service = ConnectivityService(enabled: false, directory: directory, retryDelays: [])
        var attempts = 0, accepts = false
        service.onReceive = { data in XCTAssertEqual(data, self.archive); attempts += 1; return accepts }

        await service.receiveArchive(archive).value
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(try storedArchives(in: directory).map { try Data(contentsOf: $0) }, [archive])

        accepts = true; service.refresh()
        XCTAssertEqual(attempts, 2); XCTAssertTrue(storedArchives(in: directory).isEmpty)
        service.refresh(); XCTAssertEqual(attempts, 2)
    }

    func testInboxSurvivesServiceRestartAndWaitsForInstalledCallback() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        var first: ConnectivityService? = ConnectivityService(enabled: false, directory: directory, retryDelays: [])
        await first!.receiveArchive(archive).value
        first = nil

        let restarted = ConnectivityService(enabled: false, directory: directory, retryDelays: [])
        restarted.refresh()
        XCTAssertEqual(storedArchives(in: directory).count, 1)
        var events: [String] = []
        restarted.onReceive = { data in XCTAssertEqual(data, self.archive); events.append("receive"); return true }
        restarted.onReady = { events.append("ready") }
        restarted.refresh()
        XCTAssertEqual(events, ["receive", "ready"])
        XCTAssertTrue(storedArchives(in: directory).isEmpty)
    }

    func testDuplicateFailedArchiveUsesOneDurableInboxEntry() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let service = ConnectivityService(enabled: false, directory: directory, retryDelays: [])
        service.onReceive = { _ in false }
        await service.receiveArchive(archive).value
        await service.receiveArchive(archive).value
        XCTAssertEqual(try storedArchives(in: directory).map { try Data(contentsOf: $0) }, [archive])
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testInboxWriteFailureKeepsBytesForRetryAfterStorageRecovers() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        try Data("blocks directory creation".utf8).write(to: directory)
        let service = ConnectivityService(enabled: false, directory: directory, retryDelays: [])
        var attempts = 0
        service.onReceive = { data in XCTAssertEqual(data, self.archive); attempts += 1; return attempts > 1 }
        await service.receiveArchive(archive).value
        XCTAssertEqual(attempts, 1)

        try FileManager.default.removeItem(at: directory)
        service.refresh()
        XCTAssertEqual(attempts, 2); XCTAssertTrue(storedArchives(in: directory).isEmpty)
    }

    func testFailedReceiverAutomaticallyRetriesAndClearsInboxOnSuccess() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let service = ConnectivityService(enabled: false, directory: directory, retryDelays: [0.01])
        let received = expectation(description: "receiver retried")
        var attempts = 0
        service.onReceive = { data in
            XCTAssertEqual(data, self.archive); attempts += 1
            if attempts == 2 { received.fulfill(); return true }
            return false
        }
        await service.receiveArchive(archive).value
        await fulfillment(of: [received], timeout: 1)
        XCTAssertEqual(attempts, 2); XCTAssertTrue(storedArchives(in: directory).isEmpty)
    }

    func testTransportFailureRetriesAutomaticallyWithBoundedBackoff() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let service = ConnectivityService(enabled: false, directory: directory, retryDelays: [0.01, 0.01])
        let retried = expectation(description: "two automatic retries"); retried.expectedFulfillmentCount = 2
        let error = NSError(domain: "ConnectivityServiceTests", code: 1)
        var attempts = 0
        service.onReady = { attempts += 1; retried.fulfill(); service.transferFinished(error: error) }
        service.transferFinished(error: error)
        await fulfillment(of: [retried], timeout: 1)
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(attempts, 2)

        service.onReady = { attempts += 1 }
        service.refresh(); XCTAssertEqual(attempts, 3)
    }
}
