# Native navigation fixture

`HerdrNavigationHarness` is a test-only app with a separate bundle identifier and UserDefaults suite. It mounts the production `MobileWorkspaceView`, `MobileRootView`, terminal host, preview, and settings. Only the external transport is replaced: it returns two Spaces, three server Tabs, three existing Agents, and one ordinary terminal. It does not connect to SSH or provide terminal output; it cannot validate live terminal rendering or remote authentication.

Generate the project with `xcodegen generate`, then run `HerdrNavigationAcceptance` against a dedicated iPhone Simulator. The XCTest cases use the actual drawer, Tab, pane menu, composer, and app entry controls. `HerdrMobileUIAcceptance` remains the configuration CRUD test against the formal app.

For a manual screenshot after building the fixture:

```sh
xcrun simctl install "$SIMULATOR_ID" build-ios/Build/Products/Debug-iphonesimulator/NavigationHarness.app
xcrun simctl launch "$SIMULATOR_ID" dev.bybee.herdrm.navigation-fixture -AppleLanguages '(zh-Hans)' -AppleLocale zh_Hans -app.theme dark
xcrun simctl io "$SIMULATOR_ID" screenshot /private/tmp/herdr-navigation-fixture.png
```

Use production Settings to choose language and appearance if the stored preference has already been changed. Set `SIMCTL_CHILD_NAV_HARNESS_LARGE_TEXT=1` on `simctl launch` for accessibility text. `SIMCTL_CHILD_NAV_HARNESS_RECONNECT_FAILURE=1` makes the second connection wait four seconds and fail; returning from the home screen demonstrates restoring and failure states. `SIMCTL_CHILD_NAV_HARNESS_DELETED_PANE=1` removes the selected Agent from the second connection's authoritative snapshot, demonstrating the unavailable state and explicit selection of the remaining shell pane. A new launch resets navigation memory, as in the formal app.

The large-text UI test keeps a native screenshot in its `.xcresult`. Export it with:

```sh
xcrun xcresulttool export attachments --path "$RESULT_BUNDLE" --output-path /private/tmp/herdr-navigation-attachments
```

Agent and machine artwork uses the existing Mac SVG sources. To refresh the iOS raster asset catalog after an intentional vector change, run `swift Resources/generate-brand-icons.swift` on macOS. The generated images are checked in; regeneration is not a build step.
