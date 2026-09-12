import XCTest

final class PenPhotoUITests: XCTestCase {
    @MainActor
    func testCaptureAspectSwitchPersists() {
        let app = XCUIApplication(); app.launchArguments = ["--verify-preview-lifecycle"]; app.launch()
        let button = app.buttons["captureAspect"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        if button.value as? String != "4:3" { button.tap() }
        let preview = app.otherElements["previewInstance"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        let instance = preview.value as? String
        XCTAssertNotNil(instance)
        for _ in 0..<3 {
            button.tap()
            XCTAssertEqual(button.value as? String, "16:9")
            XCTAssertEqual(preview.value as? String, instance)
            button.tap()
            XCTAssertEqual(button.value as? String, "4:3")
            XCTAssertEqual(preview.value as? String, instance)
        }
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
    func testBeautyPresetsAndComparisonInBothCaptureLayouts() {
        let app = XCUIApplication(); app.launch()
        let aspect = app.buttons["captureAspect"]
        XCTAssertTrue(aspect.waitForExistence(timeout: 10))
        if aspect.value as? String != "4:3" { aspect.tap() }
        app.buttons["ビューティー"].tap()
        XCTAssertTrue(app.segmentedControls["beautyStyle"].waitForExistence(timeout: 5))
        app.segmentedControls["beautyStyle"].buttons["明るめ"].tap()
        app.buttons["beautyCompare"].tap()
        XCTAssertTrue(app.staticTexts["加工前を表示中"].exists)
        app.buttons["beautyCompare"].tap()
        aspect.tap()
        XCTAssertEqual(aspect.value as? String, "16:9")
        app.segmentedControls["beautyStyle"].buttons["なめらか"].tap()
        XCTAssertTrue(app.buttons["beautyCompare"].isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Beauty camera controls"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["サンプルで編集を試す"].tap()
        app.buttons["写真・ビューティー"].tap()
        XCTAssertTrue(app.segmentedControls["editorBeautyStyle"].waitForExistence(timeout: 5))
        app.segmentedControls["editorBeautyStyle"].buttons["明るめ"].tap()
        app.buttons["editorBeautyCompare"].tap()
        XCTAssertTrue(app.buttons["加工後に戻す"].exists)
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
        app.buttons["rotatePhoto"].tap()
        let photo = app.images["editingPhoto"]
        let landscape = NSPredicate { _, _ in photo.exists && photo.frame.width > photo.frame.height }
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landscape, object: nil)], timeout: 5) == .completed)
        app.buttons["取り消す"].tap()
        let portrait = NSPredicate { _, _ in photo.exists && photo.frame.height > photo.frame.width }
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: portrait, object: nil)], timeout: 5) == .completed)
        app.buttons["やり直す"].tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landscape, object: nil)], timeout: 5) == .completed)
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
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landscape, object: nil)], timeout: 5) == .completed)
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

    @MainActor
    func testCropPositionCanBeAdjustedSavedReopenedAndUndone() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--sample-editor"]
        app.launch()
        let field = app.textFields["captionField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText(" / crop test")
        app.buttons["写真・ビューティー"].tap()
        let cropLabel = app.staticTexts["cropLabel"]
        XCTAssertTrue(cropLabel.waitForExistence(timeout: 5))
        XCTAssertEqual(cropLabel.label, "元の比率")
        let openCrop = app.buttons["openCropEditor"]
        XCTAssertTrue(openCrop.waitForExistence(timeout: 5))
        openCrop.tap()

        // Pick a ratio, drag to reposition, pinch to resize, then confirm.
        let ratioPicker = app.segmentedControls["cropRatioPicker"]
        XCTAssertTrue(ratioPicker.waitForExistence(timeout: 10))
        ratioPicker.buttons["4:5"].tap()
        let canvas = app.otherElements["cropCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let dragStart = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let dragEnd = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35))
        dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
        canvas.pinch(withScale: 1.4, velocity: 1)
        app.buttons["cropConfirm"].tap()
        XCTAssertTrue(cropLabel.waitForExistence(timeout: 5))
        XCTAssertEqual(cropLabel.label, "4:5")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Crop positioned"; shot.lifetime = .keepAlways; add(shot)

        // Undo/redo cover the crop confirmation like any other edit.
        XCTAssertTrue(app.buttons["取り消す"].isEnabled)
        app.buttons["取り消す"].tap()
        XCTAssertEqual(cropLabel.label, "元の比率")
        XCTAssertTrue(app.buttons["やり直す"].isEnabled)
        app.buttons["やり直す"].tap()
        XCTAssertEqual(cropLabel.label, "4:5")

        // Reopening keeps the chosen ratio so the user can keep refining the position.
        openCrop.tap()
        XCTAssertTrue(app.segmentedControls["cropRatioPicker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["cropRatioPicker"].buttons["4:5"].isSelected)
        app.buttons["cropCancel"].tap()

        // Rotating recenters the crop position but keeps the ratio (see EditorView.rotatePhoto).
        app.buttons["rotatePhoto"].tap()
        XCTAssertEqual(cropLabel.label, "4:5")

        // Saving a draft and reopening it from My Photos must keep the crop applied.
        app.buttons["下書き"].tap()
        XCTAssertTrue(app.alerts["PenPhoto"].waitForExistence(timeout: 15))
        app.alerts.buttons["OK"].tap()
        app.buttons["閉じる"].tap()
        app.buttons["マイフォト"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "crop test")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        saved.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        app.buttons["写真・ビューティー"].tap()
        XCTAssertTrue(app.staticTexts["cropLabel"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["cropLabel"].label, "4:5")

        // Clearing the crop is also available directly, without opening the position editor.
        app.buttons["clearCrop"].tap()
        XCTAssertEqual(app.staticTexts["cropLabel"].label, "元の比率")
    }
}
