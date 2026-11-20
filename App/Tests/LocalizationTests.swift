import XCTest
@testable import Enchant

final class LocalizationTests: XCTestCase {
    private func localizedBundle(_ language: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try XCTUnwrap(Bundle(path: path))
    }
    func testBothLanguagesHaveTheSameCompleteCatalog() throws {
        func strings(_ language: String, table: String = "Localizable") throws -> [String: String] {
            let url = try XCTUnwrap(try localizedBundle(language).url(forResource: table, withExtension: "strings"))
            let data = try Data(contentsOf: url)
            return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        }
        let english = try strings("en"), chinese = try strings("zh-Hans")
        XCTAssertEqual(Set(english.keys), Set(chinese.keys))
        XCTAssertGreaterThan(english.count, 100)
        let han = try NSRegularExpression(pattern: "[\\p{Han}]")
        for (key, value) in english {
            XCTAssertEqual(han.numberOfMatches(in: value, range: NSRange(value.startIndex..., in: value)), 0, key)
        }
        for language in ["en", "zh-Hans"] {
            let purpose = try strings(language, table: "InfoPlist")
            for key in ["NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription", "NSMotionUsageDescription"] {
                XCTAssertFalse(try XCTUnwrap(purpose[key]).isEmpty, key)
            }
        }
    }
    func testEnglishNamesAndChineseNoteAction() throws {
        let english = try localizedBundle("en"), chinese = try localizedBundle("zh-Hans")
        XCTAssertEqual(english.localizedString(forKey: "附魔开始", value: nil, table: "Localizable"), "Enchant")
        XCTAssertEqual(english.localizedString(forKey: "魔法手账", value: nil, table: "Localizable"), "Spellbook")
        XCTAssertEqual(english.localizedString(forKey: "备注", value: nil, table: "Localizable"), "Note")
        XCTAssertEqual(chinese.localizedString(forKey: "备注", value: nil, table: "Localizable"), "备注")
    }
    func testTranslatedFormatsKeepTheirArguments() throws {
        let english = try localizedBundle("en")
        let saved = english.localizedString(forKey: "%ld 条收藏", value: nil, table: "Localizable")
        XCTAssertEqual(String(format: saved, 1), "1 saved")
        let error = english.localizedString(forKey: "记录已被删除，草稿已保留。", value: nil, table: "Localizable")
        XCTAssertFalse(error.contains("%@"))
        let format = english.localizedString(forKey: "同步数据未接收，现有记录未更改：%@", value: nil, table: "Localizable")
        XCTAssertTrue(String(format: format, "disk full").contains("disk full"))
    }
    func testTransferStatusDoesNotClaimASuccessfulMerge() throws {
        let english = try localizedBundle("en"), chinese = try localizedBundle("zh-Hans")
        XCTAssertEqual(english.localizedString(forKey: "配对传输完成", value: nil, table: "Localizable"), "Transfer complete")
        XCTAssertEqual(english.localizedString(forKey: "配对数据已处理 · 收件清理待重试", value: nil, table: "Localizable"), "Handled · Cleanup pending")
        XCTAssertEqual(chinese.localizedString(forKey: "配对传输完成", value: nil, table: "Localizable"), "配对传输完成")
    }
    func testHeartSourceOnlyTranslatesAppOwnedMarkers() {
        let external = "我的设备 · Heart Provider"
        XCTAssertEqual(L10n.heartSource(external), external)
        let marker = "Apple Watch · 本次健康会话"
        XCTAssertEqual(L10n.heartSource(marker), L10n.text(marker))
    }
}
