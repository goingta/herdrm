import XCTest

/// Exercises the public configuration UI using an isolated temporary profile.
/// Never modifies an existing development machine or reads credentials.
final class DevelopmentMachineFormTests: XCTestCase {
    private var originallySelectedIdentifier: String?
    @MainActor
    func testTemporaryDevelopmentMachineCanBeSavedRenamedAndRemoved() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let originalChoices = deviceChoices(in: app, captureSelection: true)
        let temporaryName = "UIA-" + UUID().uuidString.prefix(8)
        let renamed = temporaryName + "-renamed"

        toolbarButton("device.add", in: app).tap()
        let name = app.textFields["device.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(temporaryName)
        fill(app.textFields["device.host"], with: "127.0.0.1", app: app)
        fill(app.textFields["device.port"], with: "1", app: app)
        fill(app.textFields["device.username"], with: "uiacceptance", app: app)
        let save = app.buttons["device.save"]
        XCTAssertTrue(save.isEnabled, "Valid connection fields enable saving")
        save.tap()
        attachment("saved temporary profile", app: app)

        openDeviceMenu(in: app)
        XCTAssertTrue(deviceChoice(named: temporaryName, in: app).waitForExistence(timeout: 3))
        app.buttons["device.edit"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, temporaryName)
        fill(name, with: renamed, app: app)
        save.tap()

        // Cold launch proves the user can retrieve the saved edit through the UI.
        app.terminate()
        app.launch()
        openDeviceMenu(in: app)
        let editedChoice = deviceChoice(named: renamed, in: app)
        XCTAssertTrue(editedChoice.waitForExistence(timeout: 3))
        editedChoice.tap()
        openDeviceMenu(in: app)
        app.buttons["device.edit"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, renamed)
        XCTAssertEqual(app.textFields["device.host"].value as? String, "127.0.0.1")
        attachment("persisted edited profile", app: app)
        app.buttons["device.cancel"].tap()

        openDeviceMenu(in: app)
        app.buttons["device.remove"].tap()
        let confirm = app.buttons.matching(identifier: "device.remove.confirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        app.terminate()
        app.launch()
        XCTAssertEqual(deviceChoices(in: app), originalChoices,
                       "Deleting the temporary profile preserves all preexisting profiles")
        if let originallySelectedIdentifier {
            openDeviceMenu(in: app)
            app.buttons[originallySelectedIdentifier].tap()
            openDeviceMenu(in: app)
            XCTAssertTrue(app.buttons[originallySelectedIdentifier].isSelected,
                          "Restore the development machine selected before acceptance")
            app.tapCoordinate(x: 0.9, y: 0.7)
        }
        attachment("temporary profile removed; original profiles retained", app: app)
    }

    @MainActor
    private func deviceChoices(in app: XCUIApplication, captureSelection: Bool = false) -> Set<String> {
        let menu = app.buttons["devices.menu"]
        guard menu.waitForExistence(timeout: 2) || app.buttons["OverflowBarButtonItem"].exists else { return [] }
        openDeviceMenu(in: app)
        let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "device.select."))
        XCTAssertGreaterThan(choices.count, 0, "An existing device menu exposes its actual profile choices")
        let elements = choices.allElementsBoundByIndex
        let result = Set(elements.map(\.identifier))
        if captureSelection {
            originallySelectedIdentifier = elements.first(where: \.isSelected)?.identifier
            XCTAssertNotNil(originallySelectedIdentifier, "Capture the publicly selected profile to restore it afterwards")
        }
        // Dismiss without selecting a different profile or touching credentials.
        app.tapCoordinate(x: 0.9, y: 0.7)
        return result
    }

    @MainActor
    private func deviceChoice(named name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "device.select.", name
        )).firstMatch
    }

    @MainActor
    private func openDeviceMenu(in app: XCUIApplication) {
        let menu = app.buttons["devices.menu"]
        if menu.waitForExistence(timeout: 2) {
            menu.tap()
        } else {
            // iOS may flatten this menu into the navigation bar's overflow.
            app.buttons["OverflowBarButtonItem"].tap()
            if !app.buttons["device.edit"].exists {
                // The overflow can present the picker as a nested submenu,
                // retaining its visible chevrons rather than the Menu's ID.
                app.buttons.containing(.image, identifier: "chevron.up.chevron.down").firstMatch.tap()
            }
        }
        XCTAssertTrue(app.buttons["device.edit"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func toolbarButton(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[identifier]
        if !button.waitForExistence(timeout: 2), app.buttons["OverflowBarButtonItem"].exists {
            openDeviceMenu(in: app)
            if identifier == "device.add", app.buttons["device.add.menu"].exists {
                return app.buttons["device.add.menu"]
            }
        }
        XCTAssertTrue(button.waitForExistence(timeout: 3), "Toolbar action is reachable including system overflow")
        return button
    }

    @MainActor
    private func fill(_ field: XCUIElement, with text: String, app: XCUIApplication) {
        for _ in 0..<5 where !field.isHittable {
            // Keep the gesture above the software keyboard, within the Form.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(field.isHittable, "Form field becomes reachable by scrolling above the keyboard")
        field.tap()
        let current = field.value as? String ?? ""
        // Placeholder is not input; text entry fields report placeholder when empty.
        if !current.isEmpty && current != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
    }

    @MainActor
    private func attachment(_ name: String, app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}

private extension XCUIApplication {
    @MainActor
    func tapCoordinate(x: CGFloat, y: CGFloat) {
        coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
    }
}
