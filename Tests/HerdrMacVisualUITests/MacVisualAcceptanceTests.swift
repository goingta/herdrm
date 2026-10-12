import XCTest

final class MacVisualAcceptanceTests: XCTestCase {
    @MainActor
    func testSettingsOfferTwoDarkPresetsAndSwitchWithoutRestartingWindow() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["VISUAL_CAPTURE_UI"] = "1"
        app.launchEnvironment["VISUAL_LANGUAGE"] = "en"
        app.launchEnvironment["VISUAL_THEME"] = "phosphor"
        app.launchEnvironment["VISUAL_SCENE"] = "settings"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        let settings = app.windows.firstMatch
        let green = app.radioButtons["Phosphor"]
        let orange = app.radioButtons["Amber"]
        XCTAssertTrue(green.waitForExistence(timeout: 3))
        XCTAssertTrue(orange.exists)
        XCTAssertEqual(green.value as? Int, 1)
        let before = XCTAttachment(screenshot: settings.screenshot())
        before.name = "color-presets-mac-settings-phosphor"; before.lifetime = .keepAlways; add(before)
        orange.tap()
        XCTAssertEqual(orange.value as? Int, 1)
        XCTAssertTrue(settings.exists)
        let after = XCTAttachment(screenshot: settings.screenshot())
        after.name = "color-presets-mac-settings-amber"; after.lifetime = .keepAlways; add(after)
        green.tap()
        XCTAssertEqual(green.value as? Int, 1)
    }

    @MainActor
    func testNativeSameDataLanguageThemeScenes() {
        continueAfterFailure = false
        for language in ["en", "zh-Hans"] {
            for theme in ["amber", "phosphor"] {
                for scene in ["sidebar", "devices", "form", "settings", "terminal", "failure", "restoring", "empty"] {
                    let app = XCUIApplication()
                    app.launchEnvironment["VISUAL_CAPTURE_UI"] = "1"
                    app.launchEnvironment["VISUAL_LANGUAGE"] = language
                    app.launchEnvironment["VISUAL_THEME"] = theme
                    app.launchEnvironment["VISUAL_SCENE"] = scene
                    app.launch()
                    XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
                    if scene == "form" { XCTAssertTrue(app.textFields["Linux · 日常开发机"].exists || app.textFields.count > 0) }
                    if scene == "devices" { XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Linux · 日常开发机")).count > 0) }
                    if scene == "sidebar" {
                        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "workspace")).count > 0)
                        let statuses = language == "en"
                            ? ["需求设计, Working", "执行命令与排查输入等待状态, Blocked", "验收结果－长中文名称跨平台测试, Completed, unread", "已查看的结果, Done", "Idle Agent, Idle"]
                            : ["需求设计, 运行中", "执行命令与排查输入等待状态, 等待输入", "验收结果－长中文名称跨平台测试, 已完成，未读", "已查看的结果, 已完成", "Idle Agent, 空闲"]
                        var actualLabels: [String] = []
                        for status in statuses {
                            let element = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", status)).firstMatch
                            XCTAssertTrue(element.exists, status)
                            actualLabels.append(element.label)
                        }
                        let labels = XCTAttachment(string: actualLabels.joined(separator: "\n"))
                        labels.name = "mac-native-\(language)-\(theme)-status-labels"
                        labels.lifetime = .keepAlways
                        add(labels)
                    }
                    sleep(1)
                    app.activate()
                    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 3))
                    let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                    shot.name = "mac-native-\(language)-\(theme)-\(scene)"
                    shot.lifetime = .keepAlways
                    add(shot)
                    app.terminate()
                }
            }
        }
    }
}
