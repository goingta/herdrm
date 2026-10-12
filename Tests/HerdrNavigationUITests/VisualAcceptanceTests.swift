import XCTest

final class VisualAcceptanceTests: XCTestCase {
    @MainActor
    func testTwoPresetSettingsRestyleBothModesAndPreserveSpaceTabAndDraft() {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans", theme: "phosphor")
        XCTAssertTrue(app.buttons["workspace.tab.read-tab"].waitForExistence(timeout: 5))
        let composer = app.textFields["agent.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap(); composer.typeText("Unsent palette draft")
        app.staticTexts["workspace.session.title"].tap()
        keep(app, "color-presets-chat-phosphor")
        app.buttons["workspace.mode.terminal"].tap()
        XCTAssertEqual(composer.value as? String, "Unsent palette draft")
        keep(app, "color-presets-terminal-phosphor")
        app.buttons["tab.settings"].tap()
        let presets = app.segmentedControls["appearance.mode"]
        XCTAssertTrue(presets.waitForExistence(timeout: 3))
        XCTAssertEqual(presets.buttons.count, 2)
        XCTAssertTrue(presets.buttons["荧绿"].isSelected)
        presets.buttons["橙光"].tap()
        XCTAssertTrue(presets.buttons["橙光"].isSelected)
        keep(app, "color-presets-settings-amber")
        let language = app.buttons["settings.language"]
        let fieldShot = XCTAttachment(screenshot: language.screenshot())
        fieldShot.name = "color-presets-language-amber"; fieldShot.lifetime = .keepAlways; add(fieldShot)
        let languagePixels = accentPixels(language)
        XCTAssertGreaterThan(languagePixels.orange, 10, "Native form controls must adopt the selected orange tint")
        XCTAssertEqual(languagePixels.green, 0, "The prior green tint must not remain cached in a fixed dark trait")
        app.buttons["tab.agent"].tap()
        XCTAssertTrue(app.buttons["workspace.tab.read-tab"].isSelected)
        XCTAssertEqual(composer.value as? String, "Unsent palette draft")
        keep(app, "color-presets-terminal-amber")
        app.buttons["workspace.mode.chat"].tap()
        XCTAssertEqual(composer.value as? String, "Unsent palette draft")
        keep(app, "color-presets-chat-amber")
        app.buttons["spaces.drawer"].tap()
        XCTAssertTrue(app.staticTexts["space.branch.visual-workspace"].waitForExistence(timeout: 3))
        keep(app, "color-presets-drawer-amber")
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "关闭侧栏", "spaces.drawer.close")).firstMatch.tap()
        app.buttons["tab.settings"].tap()
        presets.buttons["荧绿"].tap()
        XCTAssertTrue(presets.buttons["荧绿"].isSelected)
        keep(app, "color-presets-settings-phosphor")
        app.buttons["tab.agent"].tap()
        XCTAssertTrue(app.buttons["workspace.tab.read-tab"].isSelected)
        XCTAssertEqual(composer.value as? String, "Unsent palette draft")
    }

    @MainActor
    func testPhoneHeaderUsesMobileReadingScaleAndNativeButtonsKeepTheirTouchArea() {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans", theme: "phosphor")
        let title = app.staticTexts["workspace.session.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        // Reference default title is 16px/1.2, not the native 17pt headline.
        XCTAssertLessThanOrEqual(title.frame.height, 20, "Default title glyph height: \(title.frame)")
        for id in ["spaces.drawer", "workspace.more", "workspace.mode.chat", "workspace.mode.terminal"] {
            let button = app.buttons[id]
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
        keep(app, "iphone-usability-mobile-reading-scale")
        let normalHeight = title.frame.height
        app.terminate()
        let accessible = launch(language: "zh-Hans", theme: "phosphor", largeText: true)
        let enlargedTitle = accessible.staticTexts["workspace.session.title"]
        XCTAssertTrue(enlargedTitle.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(enlargedTitle.frame.height, normalHeight * 1.5)
        keep(accessible, "iphone-usability-dynamic-type-reading-scale")
    }
    @MainActor
    func testTappingOutsideChatComposerDismissesKeyboardAndKeepsDraftAndControls() {
        continueAfterFailure = false
        let app = launch(language: "en", theme: "phosphor")
        let composer = app.textFields["agent.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap(); composer.typeText("Keep this unsent draft")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.staticTexts["workspace.session.title"].tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)], timeout: 3) == .completed)
        XCTAssertEqual(composer.value as? String, "Keep this unsent draft")
        composer.tap(); composer.typeText(" continues")
        let editingDraft = composer.value as? String
        XCTAssertTrue(editingDraft?.contains("continues") == true)
        let work = app.webViews["chat.transcript"].buttons.matching(NSPredicate(format: "label CONTAINS %@", "Worked for 6s")).firstMatch
        work.tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)], timeout: 3) == .completed)
        XCTAssertEqual(composer.value as? String, editingDraft)
        XCTAssertTrue(app.webViews["chat.transcript"].descendants(matching: .any).matching(NSPredicate(format: "label == %@", "read_file · Read fixture README")).firstMatch.waitForExistence(timeout: 3))
        keep(app, "iphone-usability-chat-keyboard-dismissed")
    }

    @MainActor
    func testOutsideTapDismissesAgentAndOrdinaryShellComposerKeyboardsWithoutLosingDrafts() {
        continueAfterFailure = false
        let app = launch(language: "en", theme: "phosphor")
        app.buttons["workspace.mode.terminal"].tap()
        let agent = app.textFields["agent.composer"]
        XCTAssertTrue(agent.waitForExistence(timeout: 5))
        agent.tap(); agent.typeText("Unsent Agent draft")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.staticTexts["workspace.session.title"].tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)], timeout: 3) == .completed)
        XCTAssertEqual(agent.value as? String, "Unsent Agent draft")
        app.buttons["workspace.panes"].tap(); app.buttons["workspace.pane.shell"].tap()
        let shell = app.textFields["terminal.composer"]
        XCTAssertTrue(shell.waitForExistence(timeout: 3))
        shell.tap(); shell.typeText("Unsent shell draft")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.staticTexts["workspace.session.title"].tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)], timeout: 3) == .completed)
        XCTAssertEqual(shell.value as? String, "Unsent shell draft")
        keep(app, "iphone-usability-shell-keyboard-dismissed")
    }

    @MainActor
    func testDrawerShowsCheckoutBranchAndOmitsNumberAndNonRepositoryBranch() {
        continueAfterFailure = false
        let app = launch(language: "en", theme: "phosphor")
        XCTAssertTrue(app.buttons["spaces.drawer"].waitForExistence(timeout: 5))
        app.buttons["spaces.drawer"].tap()
        let branch = app.staticTexts["space.branch.visual-workspace"]
        XCTAssertTrue(branch.waitForExistence(timeout: 5))
        XCTAssertEqual(branch.label, "feature/mobile-controls")
        XCTAssertFalse(app.staticTexts["#1"].exists)
        XCTAssertFalse(app.staticTexts["space.branch.visual-long"].exists)
        keep(app, "iphone-usability-sidebar-branch")
    }

    @MainActor
    func testGhosttyKeyboardToggleSurvivesOpeningTapAndDismissesOnOutsideTap() {
        continueAfterFailure = false
        let app = launch(language: "en", theme: "phosphor")
        app.buttons["workspace.mode.terminal"].tap()
        let keyboard = app.buttons["agent.keyboard"]
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        XCTAssertTrue(keyboard.isHittable)
        keyboard.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.staticTexts["workspace.session.title"].tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)], timeout: 3) == .completed)
        let composer = app.textFields["agent.composer"]
        composer.tap(); composer.typeText("Composer owns these keystrokes")
        XCTAssertEqual(composer.value as? String, "Composer owns these keystrokes")
        app.buttons["terminal.modifier.ctrl"].tap()
        XCTAssertTrue(app.buttons["terminal.modifier.ctrl"].isSelected)
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)], timeout: 3) == .completed)
        XCTAssertEqual(composer.value as? String, "Composer owns these keystrokes")
        keep(app, "iphone-usability-ghostty-composer-focus")
    }

    @MainActor
    func testGhosttyKeyboardKeepsComposerAboveKeyboardAndAllowsDirectFocusTransfer() {
        continueAfterFailure = false
        let app = launch(language: "en", theme: "phosphor")
        app.buttons["workspace.mode.terminal"].tap()
        let composer = app.textFields["agent.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        let originalFrame = composer.frame
        app.buttons["agent.keyboard"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let geometry = XCTAttachment(string: "Composer \(composer.frame), keyboard \(app.keyboards.firstMatch.frame), keyboard hittable \(app.keyboards.firstMatch.isHittable)")
        geometry.lifetime = .keepAlways; add(geometry)
        keep(app, "iphone-usability-ghostty-keyboard-before-focus-transfer")
        XCTAssertLessThanOrEqual(composer.frame.maxY, app.keyboards.firstMatch.frame.minY,
            "Composer \(composer.frame) overlaps keyboard \(app.keyboards.firstMatch.frame)")
        composer.tap(); composer.typeText("Direct focus transfer preserves this draft")
        XCTAssertEqual(composer.value as? String, "Direct focus transfer preserves this draft")
        app.staticTexts["workspace.session.title"].tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)], timeout: 3) == .completed)
        XCTAssertEqual(composer.value as? String, "Direct focus transfer preserves this draft")
        XCTAssertEqual(composer.frame.minY, originalFrame.minY, accuracy: 1)
        keep(app, "iphone-usability-ghostty-keyboard-focus-transfer")
    }

    @MainActor
    func testTerminalComposerAvoidanceRestoresAfterLandscapeKeyboardAndForegroundReturn() {
        continueAfterFailure = false
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        let app = launch(language: "en", theme: "phosphor")
        app.buttons["workspace.mode.terminal"].tap()
        let composer = app.textFields["agent.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        let portraitY = composer.frame.minY
        XCUIDevice.shared.orientation = .landscapeLeft
        app.buttons["agent.keyboard"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(composer.frame.maxY, app.keyboards.firstMatch.frame.minY)
        composer.tap(); composer.typeText("Landscape draft")
        XCTAssertEqual(composer.value as? String, "Landscape draft")
        XCTAssertLessThanOrEqual(composer.frame.maxY, app.keyboards.firstMatch.frame.minY)
        keep(app, "iphone-usability-landscape-keyboard")
        XCUIDevice.shared.orientation = .portrait
        app.buttons["terminal.modifier.ctrl"].tap()
        XCTAssertTrue(app.buttons["terminal.modifier.ctrl"].isSelected)
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)], timeout: 3) == .completed)
        XCTAssertEqual(composer.frame.minY, portraitY, accuracy: 1)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, "Landscape draft")
        XCTAssertEqual(composer.frame.minY, portraitY, accuracy: 1)
    }

    @MainActor
    func testInactiveAgentKeyboardObserverLeavesPreviewWebInputsEditable() throws {
        continueAfterFailure = false
        let server = try PreviewHTTPFixture()
        let app = launch(language: "en", theme: "phosphor")
        app.buttons["tab.preview"].tap()
        let address = app.textFields["preview.address"]
        address.tap(); address.typeText("http://127.0.0.1:\(server.port)/")
        app.buttons["preview.open"].tap()
        let input = app.webViews.textFields["Preview editable input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText("Preview draft")
        input.tap(); input.typeText(" still editable")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue((input.value as? String)?.contains("still editable") == true)
        keep(app, "iphone-usability-preview-input-isolation")
    }
    @MainActor
    func testActualReferenceChatRendersCanonicalConversation() {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans", theme: "amber")
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
        app.launchEnvironment["VISUAL_THEME"] = "amber"
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
            for theme in ["amber", "phosphor"] {
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
        let app = launch(language: "zh-Hans", theme: "phosphor", largeText: true)
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
        let empty = launch(language: "en", theme: "amber", scene: "empty")
        XCTAssertTrue(empty.buttons["workspace.more"].waitForExistence(timeout: 5))
        XCTAssertFalse(empty.staticTexts["Add a Mac running herdr to get started."].exists)
        keep(empty, "\(platform)-en-light-empty")
    }

    @MainActor
    func testOrdinaryShellUsesReferenceComposerAndRetainsUnconfirmedDraft() {
        continueAfterFailure = false
        let app = launch(language: "en", theme: "phosphor")
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
        let app = launch(language: "en", theme: "phosphor")
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
        let app = launch(language: "zh-Hans", theme: "phosphor")
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

    @MainActor
    func testChatServiceSheetAppearanceAndCancelPreservesWorkspace() {
        continueAfterFailure = false
        for theme in ["amber", "phosphor"] {
            let app = launch(language: "en", theme: theme)
            XCTAssertTrue(app.buttons["workspace.tab.read-tab"].waitForExistence(timeout: 5))
            app.buttons["workspace.more"].tap()
            app.buttons["Chat Service"].tap()
            let address = app.textFields["chat.service.address"]
            XCTAssertTrue(address.waitForExistence(timeout: 3))
            XCTAssertEqual(address.value as? String, "https://visual-chat-fixture.invalid/")
            XCTAssertTrue(app.buttons["chat.service.authenticate"].isHittable)
            keep(app, "\(platform)-en-\(theme)-chat-service")
            app.buttons["Cancel"].tap()
            XCTAssertTrue(app.buttons["workspace.tab.read-tab"].isSelected)
            XCTAssertTrue(app.textFields["agent.composer"].isHittable)
            app.terminate()
        }
    }

    @MainActor private func accentPixels(_ element: XCUIElement) -> (green: Int, orange: Int) {
        let image = element.screenshot().image.cgImage!
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var green = 0, orange = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let r = bytes[i], g = bytes[i + 1], b = bytes[i + 2]
            if r < 100, g > 150, b < 100 { green += 1 }
            if r > 150, g > 80, g < 220, b < 100 { orange += 1 }
        }
        return (green, orange)
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
