import XCTest

final class SpaceNavigationTests: XCTestCase {
    @MainActor
    func testMoreOffersTerminalRefreshWithoutReconnectingOrDiscardingDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["workspace.mode.terminal"].waitForExistence(timeout: 5))
        app.buttons["workspace.mode.terminal"].tap()
        let input = app.textFields["agent.composer"]
        input.tap()
        input.typeText("Retain terminal draft")
        app.buttons["workspace.more"].tap()
        let refresh = app.buttons["workspace.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 3))
        refresh.tap()
        XCTAssertEqual(input.value as? String, "Retain terminal draft")
        XCTAssertTrue(app.buttons["workspace.mode.terminal"].isSelected)
    }

    @MainActor
    func testTerminalReferenceKeyBarHasFunctionalModifierControlsAndPillComposer() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["workspace.mode.terminal"].waitForExistence(timeout: 5))
        app.buttons["workspace.mode.terminal"].tap()
        let control = app.buttons["terminal.modifier.ctrl"]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        control.tap()
        XCTAssertTrue(control.isSelected)
        let keys = app.scrollViews["terminal.keys"]
        keys.swipeLeft()
        let shift = app.buttons["terminal.modifier.shift"]
        XCTAssertTrue(shift.isHittable)
        shift.tap()
        XCTAssertTrue(shift.isSelected)
        XCTAssertTrue(app.buttons["agent.send"].exists)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "reference-terminal-pill-and-modifiers"
        image.lifetime = .keepAlways
        add(image)
    }

    @MainActor
    func testActualChatTranscriptAndComposerSurviveModeAndBottomRootSwitches() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["NAV_HARNESS_CHAT"] = "1"
        app.launchEnvironment["NAV_HARNESS_DARK"] = "1"
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-app.language", "zh-Hans"]
        app.launch()
        XCTAssertTrue(app.webViews["chat.transcript"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["chat.model"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["workspace.mode.chat"].isSelected)
        let input = app.textFields["agent.composer"]
        input.tap()
        input.typeText("retain across modes")
        app.buttons["workspace.mode.terminal"].tap()
        app.buttons["workspace.mode.chat"].tap()
        XCTAssertEqual(input.value as? String, "retain across modes")
        app.buttons["tab.preview"].tap()
        app.buttons["tab.agent"].tap()
        XCTAssertEqual(input.value as? String, "retain across modes")
        app.buttons["tab.settings"].tap()
        app.buttons["tab.agent"].tap()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "reference-native-controlled-chat"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testReferenceHeaderShowsActualSessionAndModeControlsWithoutExtraWorkspaceHeader() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["workspace.mode.chat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["workspace.mode.terminal"].exists)
        XCTAssertTrue(app.buttons["workspace.more"].exists)
        XCTAssertFalse(app.staticTexts["workspace.title"].exists)
        XCTAssertTrue(app.buttons["workspace.panes"].exists)
        app.buttons["workspace.mode.terminal"].tap()
        XCTAssertTrue(app.buttons["workspace.mode.terminal"].isSelected)
        app.buttons["workspace.mode.chat"].tap()
        XCTAssertTrue(app.buttons["workspace.mode.chat"].isSelected)
    }

    @MainActor
    func testInitialFourthTabAndSpaceReturnKeepSelectionVisibleWithoutSwiping() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["NAV_HARNESS_MANY_TABS"] = "1"
        app.launch()
        let selected = app.buttons["workspace.tab.tab-four"]
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertTrue(selected.isSelected)
        XCTAssertTrue(selected.isHittable, "The initially focused remote tab must be visible without swiping")
        app.buttons["spaces.drawer"].tap()
        app.buttons["space.select.space-b"].tap()
        app.buttons["spaces.drawer"].tap()
        app.buttons["space.select.space-a"].tap()
        XCTAssertTrue(selected.isSelected)
        XCTAssertTrue(selected.isHittable, "A remembered tab must scroll into view after changing Space")
    }

    @MainActor
    func testAuthoritativeDeletedPaneShowsUnavailableUntilUserChoosesAnotherPane() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-app.language", "en"]
        app.launchEnvironment["NAV_HARNESS_DELETED_PANE"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["workspace.panes"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["Selected Terminal Unavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["agent.composer"].exists)
        app.buttons["workspace.panes"].tap()
        app.buttons["workspace.pane.shell-two"].tap()
        XCTAssertFalse(app.staticTexts["Selected Terminal Unavailable"].exists)
        XCTAssertTrue(app.buttons["workspace.tab.tab-two"].isSelected)
    }

    @MainActor
    func testDrawerStartsClosedAndChoosingSpaceShowsItsActualTabs() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let drawer = app.buttons["spaces.drawer"]
        XCTAssertTrue(drawer.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["space.select.space-b"].exists)
        XCTAssertTrue(app.buttons["workspace.tab.tab-two"].waitForExistence(timeout: 5))
        drawer.tap()
        let otherSpace = app.buttons["space.select.space-b"]
        XCTAssertTrue(otherSpace.waitForExistence(timeout: 3))
        otherSpace.tap()
        XCTAssertFalse(otherSpace.exists, "Choosing a Space closes the drawer")
        XCTAssertTrue(app.buttons["workspace.tab.tab-other"].exists)
        XCTAssertFalse(app.buttons["workspace.tab.tab-two"].exists, "Main pane belongs wholly to the selected Space")
    }

    @MainActor
    func testPanePickerAndSpaceTabsKeepTheirOwnDraftsAndChoices() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let picker = app.buttons["workspace.panes"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        app.buttons["workspace.pane.shell-two"].tap()
        XCTAssertFalse(app.textFields["agent.composer"].exists)
        app.buttons["workspace.tab.tab-one"].tap()
        app.buttons["workspace.tab.tab-two"].tap()
        picker.tap()
        XCTAssertTrue(app.buttons["workspace.pane.shell-two"].isSelected)
        app.buttons["workspace.pane.pane-two"].tap()
        let composer = app.textFields["agent.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 3))
        composer.tap()
        composer.typeText("retain this unsent draft")
        app.buttons["tab.preview"].tap()
        app.buttons["tab.settings"].tap()
        app.buttons["tab.agent"].tap()
        XCTAssertEqual(composer.value as? String, "retain this unsent draft")
        app.buttons["workspace.tab.tab-one"].tap()
        XCTAssertNotEqual(composer.value as? String, "retain this unsent draft")
        app.buttons["workspace.tab.tab-two"].tap()
        XCTAssertEqual(composer.value as? String, "retain this unsent draft")
    }

    @MainActor
    func testLongChineseNamesAndLargeTextKeepManagementAndTabsReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["NAV_HARNESS_LARGE_TEXT"] = "1"
        app.launch()
        for id in ["spaces.drawer", "workspace.mode.chat", "workspace.mode.terminal", "workspace.more"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertTrue(button.isHittable, "Long names never hide \(id)")
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, "44pt height: \(id), frame: \(button.frame)")
        }
        app.buttons["spaces.drawer"].tap()
        let space = app.buttons["space.select.space-b"]
        // Accessibility text can place later rows below the visible drawer.
        for _ in 0..<3 where !space.isHittable { app.scrollViews["spaces.sidebar"].swipeUp() }
        XCTAssertTrue(space.isHittable)
        XCTAssertGreaterThanOrEqual(space.frame.height, 44)
        space.tap()
        XCTAssertTrue(app.buttons["workspace.tab.tab-other"].isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Native fixture — Chinese names and accessibility text"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testSelectedTerminalShowsRecoveryAndFailureAfterReturningFromBackground() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-app.language", "en"]
        app.launchEnvironment["NAV_HARNESS_RECONNECT_FAILURE"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["workspace.panes"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["Restoring Terminal…"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["No Agent Selected"].exists)
        XCTAssertTrue(app.staticTexts["Connection Failed"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.staticTexts["No Agent Selected"].exists)
        XCTAssertTrue(app.buttons["workspace.tab.tab-two"].isSelected)
    }
}
