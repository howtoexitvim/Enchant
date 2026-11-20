import XCTest
final class EnchantUITests: XCTestCase {
    func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
    func app(demo: Bool = false) -> XCUIApplication { let app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + (demo ? ["-demo"] : []); app.launch(); return app }
    func testManualSessionPauseFinishAndReopen() {
        let a = app(); a.buttons["附魔开始"].tap()
        XCTAssertTrue(a.buttons["暂停"].waitForExistence(timeout: 5)); a.buttons["暂停"].tap()
        XCTAssertTrue(a.buttons["继续"].exists); a.buttons["继续"].tap(); a.buttons["结束附魔"].tap()
        XCTAssertTrue(a.staticTexts["附魔完成"].waitForExistence(timeout: 5))
        XCTAssertTrue(a.buttons["完成"].isHittable); XCTAssertTrue(a.buttons["备注"].isHittable); capture("Phone Chinese result", app: a)
        a.buttons["完成"].tap()
        a.tabBars.buttons["手账"].tap(); XCTAssertTrue(a.buttons["record-row"].firstMatch.waitForExistence(timeout: 5))
        a.terminate(); a.launchArguments = ["-ui-testing", "-keep-data", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]; a.launch(); a.tabBars.buttons["手账"].tap()
        XCTAssertTrue(a.buttons["record-row"].firstMatch.waitForExistence(timeout: 5))
    }
    func testNoteWithInlineLinkDeleteAndRestore() {
        let a = app(demo: true); a.tabBars.buttons["手账"].tap(); a.buttons["record-row"].firstMatch.tap()
        a.segmentedControls.buttons["手账"].tap(); a.buttons["编辑备注"].tap()
        let note = a.textViews["记录备注"]; note.tap()
        note.typeText("\nA local note https://example.com\n")
        a.buttons["保存备注"].tap()
        // Attributed notes expose different accessibility roles when links are present.
        XCTAssertTrue(a.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "A local note")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(a.buttons["添加链接"].exists)
        a.buttons["记录操作"].tap(); a.buttons["删除记录"].tap(); a.alerts.buttons["移到回收站"].tap()
        a.tabBars.buttons["设置"].tap(); a.buttons["回收站"].tap(); a.buttons["恢复"].firstMatch.tap()
        XCTAssertTrue(a.staticTexts["回收站为空"].waitForExistence(timeout: 5))
    }
    func testYearCalendarAndSearch() {
        let a = app(demo: true); a.tabBars.buttons["手账"].tap(); a.buttons["年"].tap(); XCTAssertTrue(a.buttons["10月"].exists); a.buttons["10月"].tap()
        a.textFields["搜索记录"].tap(); a.textFields["搜索记录"].typeText("demo")
        XCTAssertTrue(a.buttons["record-row"].firstMatch.waitForExistence(timeout: 5)); XCTAssertTrue(a.buttons["record-row"].firstMatch.isHittable)
        a.buttons["取消"].tap(); XCTAssertTrue(a.buttons["年"].isHittable)
    }

    func testCancelNoteKeepsSavedRecordAndResumesDraft() throws {
        let a = app(demo: true)
        a.tabBars.buttons["手账"].tap()
        let row = a.buttons["record-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        a.segmentedControls.buttons["手账"].tap(); a.buttons["编辑备注"].tap()
        let note = a.textViews["记录备注"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        let savedNote = try XCTUnwrap(note.value as? String)
        XCTAssertFalse(savedNote.isEmpty)
        let draftMarker = "Unsaved cancellation draft"
        note.tap(); note.typeText("\n\(draftMarker)\n")
        a.buttons["取消"].tap()

        let savedText = a.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", savedNote)).firstMatch
        XCTAssertTrue(savedText.waitForExistence(timeout: 5))
        XCTAssertFalse(a.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", draftMarker)).firstMatch.exists)
        a.buttons["编辑备注"].tap()
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertTrue(try XCTUnwrap(note.value as? String).contains(draftMarker))
        a.buttons["取消"].tap()
        XCTAssertTrue(savedText.waitForExistence(timeout: 5))
    }

    func testEmptyJournalAndUnmatchedSearchReturnToCalendar() {
        let a = app()
        a.tabBars.buttons["手账"].tap()
        XCTAssertTrue(a.staticTexts["这页还空着"].waitForExistence(timeout: 5))
        XCTAssertFalse(a.buttons["record-row"].firstMatch.exists)
        let search = a.textFields["搜索记录"]
        search.tap(); search.typeText("no matching journal entry")
        XCTAssertTrue(a.staticTexts["没有匹配记录"].waitForExistence(timeout: 5))
        XCTAssertFalse(a.buttons["record-row"].firstMatch.exists)
        XCTAssertTrue(a.buttons["取消"].isHittable); a.buttons["取消"].tap()
        XCTAssertTrue(a.staticTexts["这页还空着"].waitForExistence(timeout: 5))
        XCTAssertTrue(a.buttons["年"].isHittable); XCTAssertTrue(a.buttons["今天"].isHittable)
        a.tabBars.buttons["设置"].tap(); a.buttons["回收站"].tap()
        XCTAssertTrue(a.staticTexts["回收站为空"].waitForExistence(timeout: 5))
    }

    func testPreferenceChangesPersistAcrossRelaunch() throws {
        let a = app(demo: true)
        a.tabBars.buttons["设置"].tap()
        var expected: [String: String] = [:]
        for title in ["自动开始", "静止提醒", "声音", "触感"] {
            let setting = a.switches[title]
            XCTAssertTrue(setting.waitForExistence(timeout: 5)); XCTAssertTrue(setting.isHittable)
            let initial = try XCTUnwrap(setting.value as? String)
            XCTAssertTrue(["0", "1"].contains(initial))
            expected[title] = initial == "1" ? "0" : "1"
            setting.tap()
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected[title]!), object: setting)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, title)
        }
        a.terminate(); a.launchArguments = ["-ui-testing", "-demo", "-keep-data", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]; a.launch()
        a.tabBars.buttons["设置"].tap()
        for (title, value) in expected {
            let setting = a.switches[title]
            XCTAssertTrue(setting.waitForExistence(timeout: 5))
            XCTAssertEqual(setting.value as? String, value, title)
        }
    }


    func testCoreScreensFitWithoutVerticalScroll() {
        let a = app(demo: true)
        XCTAssertTrue(a.buttons["附魔开始"].isHittable); capture("Phone Chinese home", app: a)
        a.tabBars.buttons["设置"].tap(); capture("Phone Chinese settings", app: a)
        for title in ["自动开始", "静止提醒", "记录心率", "声音", "触感"] { XCTAssertTrue(a.switches[title].isHittable, title) }
        XCTAssertTrue(a.buttons["回收站"].isHittable)
        XCTAssertFalse(a.buttons["导出备份"].exists); XCTAssertFalse(a.buttons["导入备份"].exists)
        a.tabBars.buttons["手账"].tap(); XCTAssertFalse(a.buttons["补记"].exists); XCTAssertTrue(a.textFields["搜索记录"].isHittable)
        a.buttons["record-row"].firstMatch.tap()
        XCTAssertTrue(a.buttons["编辑备注"].isHittable)
        XCTAssertTrue(a.staticTexts["本次心率"].exists)
    }
    func testEnglishFollowsSystemLanguageAndKeepsNotesUnchanged() {
        let a = XCUIApplication()
        a.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        a.launch()
        XCTAssertTrue(a.buttons["start-enchantment"].waitForExistence(timeout: 5))
        XCTAssertTrue(a.tabBars.buttons["Journal"].exists); XCTAssertTrue(a.tabBars.buttons["Settings"].exists)
        capture("Phone English home", app: a)
        a.tabBars.buttons["Settings"].tap(); capture("Phone English settings", app: a)
        XCTAssertTrue(a.switches["Auto start"].isHittable)
        XCTAssertFalse(a.staticTexts["偏好设置"].exists)
        a.tabBars.buttons["Enchant"].tap(); a.buttons["start-enchantment"].tap()
        XCTAssertTrue(a.buttons["Pause"].waitForExistence(timeout: 5)); a.buttons["Pause"].tap()
        XCTAssertTrue(a.buttons["Resume"].exists); a.buttons["Resume"].tap(); a.buttons["End enchantment"].tap()
        XCTAssertTrue(a.staticTexts["Enchanted"].waitForExistence(timeout: 5))
        XCTAssertTrue(a.buttons["Note"].isHittable); XCTAssertTrue(a.buttons["Done"].isHittable)
        capture("Phone English result", app: a)
        a.buttons["Note"].tap()
        let editor = a.textViews["Session note"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap()
        editor.typeText("A quiet moment https://example.com")
        a.buttons["Save note"].tap()
        a.buttons["Done"].tap(); a.tabBars.buttons["Journal"].tap(); a.buttons["record-row"].firstMatch.tap()
        a.segmentedControls.buttons["Journal"].tap()
        XCTAssertTrue(a.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "A quiet moment https://example.com")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(a.buttons["Language"].exists)
        a.terminate()
        a.launchArguments = ["-ui-testing", "-keep-data", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        a.launch(); a.tabBars.buttons["手账"].tap(); a.buttons["record-row"].firstMatch.tap()
        a.segmentedControls.buttons["手账"].tap()
        XCTAssertTrue(a.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "A quiet moment https://example.com")).firstMatch.waitForExistence(timeout: 5))
    }

}
