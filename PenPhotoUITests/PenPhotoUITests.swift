import XCTest

final class PenPhotoUITests: XCTestCase {
    @MainActor
    func testCaptureAspectSwitchPersists() {
        let app = XCUIApplication(); app.launch()
        let button = app.buttons["captureAspect"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        if button.value as? String != "4:3" { button.tap() }
        button.tap()
        XCTAssertEqual(button.value as? String, "16:9")
        let viewfinder = app.descendants(matching: .any)["wideViewfinder"].firstMatch
        XCTAssertTrue(viewfinder.waitForExistence(timeout: 5))
        XCTAssertEqual(viewfinder.frame.width, app.frame.width, accuracy: 1)
        XCTAssertEqual(viewfinder.frame.minX, app.frame.minX, accuracy: 1)
        XCTAssertEqual(viewfinder.frame.height / viewfinder.frame.width, 16.0 / 9.0, accuracy: 0.01)
        XCTAssertTrue(app.buttons["importPhoto"].isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Wide capture"; shot.lifetime = .keepAlways; add(shot)
        app.terminate(); app.launch()
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        XCTAssertEqual(button.value as? String, "16:9")
        button.tap()
        XCTAssertEqual(button.value as? String, "4:3")
    }

    @MainActor
    func testSampleCanBeEditedSavedReopenedAndExported() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--sample-editor"]
        app.launch()
        let field = app.textFields["captionField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText(" / UI test")
        app.buttons["完了"].tap()
        app.buttons["下書き"].tap()
        XCTAssertTrue(app.alerts["PenPhoto"].waitForExistence(timeout: 15))
        app.alerts.buttons["OK"].tap()
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Editor"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["閉じる"].tap()
        app.buttons["マイフォト"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "UI test")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        saved.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue((field.value as? String)?.contains("UI test") == true)
        addUIInterruptionMonitor(withDescription: "Photos access") { alert in
            let allow = alert.buttons.matching(NSPredicate(format: "label CONTAINS '許可' AND NOT label CONTAINS 'しない'")).firstMatch
            if allow.exists { allow.tap(); return true }
            if alert.buttons["Allow Access to Add Photos"].exists { alert.buttons["Allow Access to Add Photos"].tap(); return true }
            return false
        }
        app.buttons["写真に保存"].tap()
        // Trigger registered interruption handling if a permission dialog appears.
        if !app.alerts["PenPhoto"].waitForExistence(timeout: 4) { app.tap() }
        XCTAssertTrue(app.alerts["PenPhoto"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.alerts.staticTexts["コメント入りの写真を写真アプリに保存しました。マイフォトから再編集できます。"].exists)
        app.alerts.buttons["OK"].tap()
    }
}
