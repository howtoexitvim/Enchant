import XCTest
@testable import EnchantCore

final class MetadataTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_728_403_200)

    func testNewRecordDistinguishesNoMotionSamplesFromMeasuredZero() throws {
        let record = SessionRecord(startedAt: start)
        let object = try json(record)
        XCTAssertEqual(object["motionSampleCount"] as? Int, 0)
    }

    func testSensorMetadataSurvivesArchiveRoundTrip() throws {
        var record = SessionRecord(startedAt: start)
        record.heartSamples = [HeartSample(date: start, bpm: 80, source: "Watch")]
        var object = try json(record)
        object["motionSampleCount"] = 12
        var hearts = object["heartSamples"] as! [[String: Any]]
        hearts[0]["identity"] = "health-container:measurement"
        object["heartSamples"] = hearts
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: JSONSerialization.data(withJSONObject: object))
        let restored = try json(decoded)
        XCTAssertEqual(restored["motionSampleCount"] as? Int, 12)
        XCTAssertEqual((restored["heartSamples"] as! [[String: Any]])[0]["identity"] as? String, "health-container:measurement")
    }

    func testLegacyArchiveRemainsReadableWithoutNewMetadata() throws {
        var object = try json(SessionRecord(startedAt: start))
        object.removeValue(forKey: "motionSampleCount")
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.startedAt, start)
        XCTAssertEqual(decoded.estimatedCycles, 0)
        XCTAssertNil(try json(decoded)["motionSampleCount"])
    }

    private func json(_ record: SessionRecord) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as! [String: Any]
    }
}
