import XCTest

final class VisualAcceptanceTests: XCTestCase {
    @MainActor
    func testActualReferenceChatRendersCanonicalConversation() {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans", theme: "light")
        XCTAssertTrue(app.buttons["workspace.mode.chat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["workspace.mode.chat"].isSelected)
        XCTAssertTrue(app.webViews["chat.transcript"].staticTexts["SAME_CHAT_FIXTURE_RESULT"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["chat.model"].exists)
        let work = app.webViews["chat.transcript"].buttons.matching(NSPredicate(format: "label CONTAINS %@", "工作了 6 秒")).firstMatch
        let row = app.webViews["chat.transcript"].descendants(matching: .any).matching(NSPredicate(format: "label == %@", "read_file · Read fixture README")).firstMatch
        XCTAssertTrue(work.waitForExistence(timeout: 3))
        XCTAssertFalse(row.exists)
        keep(app, "\(platform)-zh-Hans-light-work-initial")
        work.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        keep(app, "\(platform)-zh-Hans-light-work-expanded")
        let geometry = XCTAttachment(string: "Expanded header \(work.frame), label \(work.label), hittable \(work.isHittable)")
        geometry.lifetime = .keepAlways; add(geometry)
        work.tap()
        keep(app, "\(platform)-zh-Hans-light-work-reclosed")
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: row)], timeout: 3) == .completed)
    }
    @MainActor
    func testSameDataFixtureUsesChineseChromeAndRemoteNames() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["VISUAL_ACCEPTANCE"] = "1"
        app.launchEnvironment["VISUAL_LANGUAGE"] = "zh-Hans"
        app.launchEnvironment["VISUAL_THEME"] = "light"
        app.launch()
        app.buttons["spaces.drawer"].tap()
        XCTAssertTrue(app.staticTexts["Linux · 日常开发机"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["space.select.visual-workspace"].exists)
        XCTAssertTrue(app.buttons["tab.preview"].label.contains("项目预览"))
    }
    @MainActor
    func testRenderedLanguageThemeMatrixAndPreviewDraftRoundTrip() throws {
        let server = try PreviewHTTPFixture()
        continueAfterFailure = false
        for language in ["en", "zh-Hans"] {
            for theme in ["light", "dark"] {
                let app = launch(language: language, theme: theme)
                XCTAssertTrue(app.buttons["workspace.tab.read-tab"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.buttons["workspace.tab.read-tab"].isHittable)
                let prefix = "\(platform)-\(language)-\(theme)"
                XCTAssertTrue(app.webViews["chat.transcript"].staticTexts["SAME_CHAT_FIXTURE_RESULT"].waitForExistence(timeout: 8))
                let work = app.webViews["chat.transcript"].buttons.matching(NSPredicate(format: "label CONTAINS %@", language == "en" ? "Worked for 6s" : "工作了 6 秒")).firstMatch
                XCTAssertTrue(work.waitForExistence(timeout: 3), "Completed work must share the reference's grouped block")
                XCTAssertTrue(work.label.contains(language == "en" ? "1 file read" : "读取 1 个文件"))
                let toolRow = app.webViews["chat.transcript"].descendants(matching: .any).matching(NSPredicate(format: "label == %@", "read_file · Read fixture README")).firstMatch
                XCTAssertFalse(toolRow.exists, "Collapsed work must hide actual tool rows, not just change its header")
                work.tap()
                XCTAssertTrue(toolRow.waitForExistence(timeout: 3), "Expanding grouped work exposes its real tool row")
                XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "⌄"), object: work)], timeout: 3) == .completed)
                XCTAssertTrue(work.isHittable)
                keep(app, prefix + "-work-expanded")
                work.tap()
                XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "›"), object: work)], timeout: 3) == .completed)
                XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: toolRow)], timeout: 3) == .completed)
                XCTAssertFalse(app.staticTexts["workspace.title"].exists)
                XCTAssertFalse(app.buttons["space.select.visual-long"].exists)
                keep(app, prefix + "-chat")
                app.buttons["spaces.drawer"].tap()
                XCTAssertTrue(app.buttons["space.select.visual-long"].isHittable)
                keep(app, prefix + "-sidebar")
                app.buttons["space.select.visual-workspace"].tap()
                let composer = app.textFields["agent.composer"]
                XCTAssertTrue(composer.waitForExistence(timeout: 3))
                composer.tap()
                composer.typeText("Unsent draft 0123")
                keep(app, prefix + "-keyboard")
                XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
                XCTAssertEqual(composer.value as? String, "Unsent draft 0123")
                XCTAssertLessThan(composer.frame.maxY, app.keyboards.firstMatch.frame.minY)
                app.buttons["workspace.mode.terminal"].tap()
                XCTAssertTrue(app.buttons["workspace.mode.terminal"].isSelected)
                keep(app, prefix + "-terminal-mode")
                app.buttons["workspace.mode.chat"].tap()
                XCTAssertEqual(composer.value as? String, "Unsent draft 0123")
                app.buttons["tab.settings"].tap()
                keep(app, prefix + "-settings")
                app.buttons["tab.agent"].tap()
                XCTAssertEqual(composer.value as? String, "Unsent draft 0123")
                app.buttons["workspace.more"].tap()
                                app.buttons[language == "en" ? "Add Development Machine" : "添加开发机"].tap()
                XCTAssertTrue(app.textFields["device.host"].waitForExistence(timeout: 3))
                keep(app, prefix + "-form")
                app.buttons["device.cancel"].tap()
                app.buttons["workspace.more"].tap()
                app.buttons[language == "en" ? "Edit Development Machine" : "编辑开发机"].tap()
                XCTAssertEqual(app.textFields["device.host"].value as? String, "fixture.invalid")
                keep(app, prefix + "-edit-form")
                app.buttons["device.cancel"].tap()
                app.buttons["tab.preview"].tap()
                let address = app.textFields["preview.address"]
                XCTAssertTrue(address.waitForExistence(timeout: 3))
                address.tap()
                address.typeText("http://127.0.0.1:\(server.port)/index.html")
                app.buttons["preview.open"].tap()
                XCTAssertTrue(app.webViews.staticTexts["VISUAL_PROJECT_PREVIEW"].waitForExistence(timeout: 8))
                keep(app, prefix + "-preview")
                app.webViews.links["Second page"].tap()
                XCTAssertTrue(app.webViews.staticTexts["VISUAL_SECOND_PAGE"].waitForExistence(timeout: 5))
                app.buttons[language == "en" ? "Back" : "返回"].tap()
                XCTAssertTrue(app.webViews.staticTexts["VISUAL_PROJECT_PREVIEW"].waitForExistence(timeout: 5))
                app.buttons["tab.agent"].tap()
                XCTAssertEqual(composer.value as? String, "Unsent draft 0123")
                XCTAssertTrue(app.buttons["workspace.tab.read-tab"].isSelected)
                app.terminate()
                let terminal = launch(language: language, theme: theme, scene: "terminal")
                sleep(2)
                keep(terminal, prefix + "-terminal-renderer")
                terminal.terminate()
            }
        }
    }

    @MainActor
    func testAccessibilityTextAndEmptyStateHaveReachableEntries() {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans", theme: "dark", largeText: true)
        // Physical-device AX frames can round 44pt to 43.99999999999999.
        for id in ["spaces.drawer", "workspace.mode.chat", "workspace.mode.terminal", "workspace.more", "tab.agent", "tab.preview", "tab.settings"] {
            let control = app.buttons[id]
            XCTAssertTrue(control.waitForExistence(timeout: 5))
            XCTAssertTrue(control.isHittable)
            XCTAssertGreaterThanOrEqual(control.frame.width + 0.000001, 44)
            XCTAssertGreaterThanOrEqual(control.frame.height + 0.000001, 44)
        }
        keep(app, "\(platform)-zh-Hans-dark-accessibility3")
        app.buttons["spaces.drawer"].tap()
        let long = app.buttons["space.select.visual-long"]
        XCTAssertTrue(long.isHittable)
        XCTAssertGreaterThanOrEqual(long.frame.height + 0.000001, 44)
        long.tap()
        XCTAssertTrue(app.buttons["workspace.tab.long-tab"].isHittable)
        for id in ["spaces.drawer", "workspace.mode.chat", "workspace.mode.terminal", "workspace.more"] {
            XCTAssertTrue(app.buttons[id].isHittable, "Long selected Space must keep header control reachable: \(id)")
        }
        XCTAssertTrue(app.webViews["chat.transcript"].staticTexts["SAME_CHAT_FIXTURE_RESULT"].waitForExistence(timeout: 8))
        keep(app, "\(platform)-zh-Hans-dark-accessibility3-long-space")
        app.terminate()
        let empty = launch(language: "en", theme: "light", scene: "empty")
        XCTAssertTrue(empty.buttons["workspace.more"].waitForExistence(timeout: 5))
        XCTAssertFalse(empty.staticTexts["Add a Mac running herdr to get started."].exists)
        keep(empty, "\(platform)-en-light-empty")
    }

    @MainActor
    func testOrdinaryShellUsesReferenceComposerAndRetainsUnconfirmedDraft() {
        continueAfterFailure = false
        let app = launch(language: "en", theme: "dark")
        XCTAssertTrue(app.buttons["workspace.panes"].waitForExistence(timeout: 5))
        app.buttons["workspace.panes"].tap()
        app.buttons["workspace.pane.shell"].tap()
        let composer = app.textFields["terminal.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["workspace.mode.terminal"].isSelected)
        XCTAssertFalse(app.buttons["workspace.mode.chat"].isEnabled)
        XCTAssertGreaterThanOrEqual(app.buttons["terminal.send"].frame.width + 0.000001, 44)
        keep(app, "\(platform)-en-dark-ordinary-shell")
        composer.tap()
        composer.typeText("Unsent shell fixture text")
        app.buttons["terminal.send"].tap()
        XCTAssertTrue(app.staticTexts["Input not confirmed. Draft retained; check the terminal before retrying."].waitForExistence(timeout: 3))
        XCTAssertEqual(composer.value as? String, "Unsent shell fixture text")
        keep(app, "\(platform)-en-dark-ordinary-shell-unconfirmed-input")
        app.buttons["tab.preview"].tap()
        app.buttons["tab.agent"].tap()
        XCTAssertEqual(composer.value as? String, "Unsent shell fixture text")
        XCTAssertTrue(app.buttons["workspace.tab.read-tab"].isSelected)
    }

    @MainActor
    func testDrawerAndConfigurationSheetOccludeThenRetainActualReply() {
        continueAfterFailure = false
        let app = launch(language: "en", theme: "dark")
        let transcript = app.webViews["chat.transcript"]
        let reply = transcript.staticTexts["SAME_CHAT_FIXTURE_RESULT"]
        XCTAssertTrue(reply.waitForExistence(timeout: 8))
        let originalFrame = reply.frame
        app.buttons["spaces.drawer"].tap()
        XCTAssertTrue(app.buttons["space.select.visual-long"].isHittable)
        keep(app, "\(platform)-en-dark-drawer-occludes-chat")
        XCTAssertTrue(waitUntilUnhittable(reply), "Occluded transcript must not claim a visible reply")
        app.buttons["spaces.drawer"].tap()
        XCTAssertTrue(reply.waitForExistence(timeout: 3))
        app.buttons["workspace.more"].tap()
        app.buttons["Add Development Machine"].tap()
        XCTAssertTrue(app.textFields["device.host"].waitForExistence(timeout: 3))
        keep(app, "\(platform)-en-dark-configuration-occludes-chat")
        XCTAssertTrue(waitUntilUnhittable(reply), "Modal configuration must not claim a visible reply")
        app.buttons["device.cancel"].tap()
        XCTAssertTrue(reply.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["workspace.tab.read-tab"].isSelected)
        XCTAssertTrue(app.buttons["workspace.mode.chat"].isSelected)
        XCTAssertEqual(reply.frame.minY, originalFrame.minY, accuracy: 1)
        keep(app, "\(platform)-en-dark-overlay-return-chat")
    }

    @MainActor
    func testCachedConversationAndSelectionRemainOnForegroundReturn() {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans", theme: "dark")
        let text = app.webViews["chat.transcript"].staticTexts["SAME_CHAT_FIXTURE_RESULT"]
        XCTAssertTrue(text.waitForExistence(timeout: 8))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["workspace.tab.read-tab"].isSelected)
        XCTAssertTrue(app.buttons["workspace.mode.chat"].isSelected)
        XCTAssertFalse(app.staticTexts["No Agent Selected"].exists)
        keep(app, "\(platform)-zh-Hans-dark-chat-resume")
    }

    @MainActor private func waitUntilUnhittable(_ element: XCUIElement) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == false"), object: element)], timeout: 3) == .completed
    }

    private var platform: String {
        #if targetEnvironment(simulator)
        return "iphone-simulator"
        #else
        return "iphone-physical"
        #endif
    }

    @MainActor private func launch(language: String, theme: String, scene: String = "workspace", largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["VISUAL_ACCEPTANCE"] = "1"
        app.launchEnvironment["VISUAL_LANGUAGE"] = language
        app.launchEnvironment["VISUAL_THEME"] = theme
        app.launchEnvironment["VISUAL_SCENE"] = scene
        if largeText { app.launchEnvironment["NAV_HARNESS_LARGE_TEXT"] = "1" }
        app.launch()
        return app
    }
    @MainActor private func keep(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

}
