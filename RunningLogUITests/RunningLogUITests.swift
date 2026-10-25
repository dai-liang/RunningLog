import XCTest

/// 使用独有备注定位本次测试创建的记录，验证真实表单、磁盘保存及编辑链路。
final class RunningLogUITests: XCTestCase {
    @MainActor
    func testAddEditAndPersistence() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["记录"].tap()
        // 只清理此前失败运行遗留的、带专用前缀的测试记录。
        let leftovers = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@", "record-", "界面验证-"))
        for leftover in leftovers.allElementsBoundByIndex {
            let identifier = leftover.identifier
            leftover.swipeLeft()
            app.buttons["删除"].tap(); app.buttons["删除记录"].tap()
            let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons[identifier])
            XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 5), .completed)
        }
        app.buttons["addRecord"].tap()
        let distance = app.textFields["recordDistance"]
        XCTAssertTrue(distance.waitForExistence(timeout: 5))
        distance.tap(); distance.typeText("5.25")
        let marker = "界面验证-" + String(UUID().uuidString.prefix(8))
        let note = app.textFields["recordNote"]
        // 多行 TextField 在不同 iOS 版本可能映射为文本框或文本视图。
        let field = note.exists ? note : app.textViews["recordNote"]
        field.tap(); field.typeText(marker)
        app.buttons["saveRecord"].tap()
        let row = app.buttons["record-" + marker]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["saveRecord"].waitForExistence(timeout: 5))
        // 表单按需创建屏幕外的行，先滚动到备注，不能用不可见元素推断控件类型。
        app.swipeUp()
        XCTAssertTrue(app.textFields["recordNote"].waitForExistence(timeout: 5))
        let editor = XCTAttachment(screenshot: app.screenshot())
        editor.name = "编辑跑步"; editor.lifetime = .keepAlways
        add(editor)
        let editNote = app.textFields["recordNote"].exists ? app.textFields["recordNote"] : app.textViews["recordNote"]
        editNote.tap(); editNote.typeText("-已编辑")
        // 点击文本时系统可能将光标置于开头；验证实际编辑值，不假定光标在末尾。
        let editedValue = try XCTUnwrap(editNote.value as? String)
        XCTAssertTrue(editedValue.contains(marker))
        XCTAssertTrue(editedValue.contains("已编辑"))
        app.buttons["saveRecord"].tap()
        XCTAssertTrue(app.buttons["record-" + editedValue].waitForExistence(timeout: 5))
        // 终止进程后重新启动，确保读到的是磁盘记录，而非内存缓存。
        app.terminate(); app.launch()
        app.tabBars.buttons["记录"].tap()
        XCTAssertTrue(app.buttons["record-" + editedValue].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "记录新增编辑与重启验证"; screenshot.lifetime = .keepAlways
        add(screenshot)
        app.tabBars.buttons["概览"].tap()
        let overview = XCTAttachment(screenshot: app.screenshot())
        overview.name = "跑步概览"; overview.lifetime = .keepAlways
        add(overview)
        // 清理仅由本测试创建的记录，避免把测试跑步混入用户后续统计。
        app.tabBars.buttons["记录"].tap()
        app.buttons["record-" + editedValue].swipeLeft()
        app.buttons["删除"].tap()
        app.buttons["删除记录"].tap()
        // 删除行带系统动画，等待可访问性树完成更新后再断言。
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["record-" + editedValue])
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 5), .completed)
    }
}
