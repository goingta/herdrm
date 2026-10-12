# Native navigation fixture

`HerdrNavigationHarness` is a test-only app with a separate bundle identifier and UserDefaults suite. It mounts the production `MobileWorkspaceView`, `MobileRootView`, terminal host, preview, and settings. Only the external transport is replaced: it returns two Spaces, three server Tabs, three existing Agents, and one ordinary terminal. It does not connect to SSH or provide terminal output; it cannot validate live terminal rendering or remote authentication.

Generate the project with `xcodegen generate`, then run `HerdrNavigationAcceptance` against a dedicated iPhone Simulator. The XCTest cases use the actual drawer, Tab, pane menu, composer, and app entry controls. `HerdrMobileUIAcceptance` remains the configuration CRUD test against the formal app.

For a manual screenshot after building the fixture:

```sh
xcrun simctl install "$SIMULATOR_ID" build-ios/Build/Products/Debug-iphonesimulator/NavigationHarness.app
xcrun simctl launch "$SIMULATOR_ID" dev.bybee.herdrm.navigation-fixture -AppleLanguages '(zh-Hans)' -AppleLocale zh_Hans -app.theme phosphor
xcrun simctl io "$SIMULATOR_ID" screenshot /private/tmp/herdr-navigation-fixture.png
```

Use production Settings to choose language and appearance if the stored preference has already been changed. Set `SIMCTL_CHILD_NAV_HARNESS_LARGE_TEXT=1` on `simctl launch` for accessibility text. `SIMCTL_CHILD_NAV_HARNESS_RECONNECT_FAILURE=1` makes a foreground validation fail, then the replacement connection waits four seconds and fails; returning from the home screen demonstrates a compact restoring/failure banner over the retained terminal. `SIMCTL_CHILD_NAV_HARNESS_DELETED_PANE=1` removes the selected Agent from the foreground validation's authoritative snapshot, demonstrating the unavailable state and explicit selection of the remaining shell pane. A new launch resets navigation memory, as in the formal app. `SIMCTL_CHILD_NAV_HARNESS_MANY_TABS=1` provides five ordered Tabs with the fourth initially selected, for native visibility regression testing. Healthy foreground returns use the production `resumeSelected()` validation path and preserve the held transport.

The large-text UI test keeps a native screenshot in its `.xcresult`. Export it with:

```sh
xcrun xcresulttool export attachments --path "$RESULT_BUNDLE" --output-path /private/tmp/herdr-navigation-attachments
```

Agent and machine artwork uses the existing Mac SVG sources. To refresh the iOS raster asset catalog after an intentional vector change, run `swift Resources/generate-brand-icons.swift` on macOS. The generated images are checked in; regeneration is not a build step.

## Same-data visual acceptance

`VISUAL_ACCEPTANCE=1` selects `Tests/VisualAcceptance/scene.json`: the same machine, Spaces, remote Tabs, Agents and UTF-8/ANSI terminal bytes used by `HerdrMacVisualAcceptance`. This independent app is displayed as **Herdr UI Fixture**. Its isolated defaults are reset for each launch, and its public-key provider is a literal test string; form screenshots do not invoke Keychain. It cannot authenticate to a real server.

Run only `HerdrNavigationUITests/VisualAcceptanceTests` in the `HerdrNavigationAcceptance` scheme for the language/theme matrix, actual form/settings/drawer/composer controls, and actual WKWebView navigation. The UI runner serves an ephemeral local HTTP page on the test device, so the same suite runs on Simulator or a connected iPhone without a Mac web server. No prompts are sent. `VISUAL_SCENE=terminal` mounts the actual Ghostty terminal view with controlled in-memory bytes; this is renderer evidence, not live SSH.

For Mac, `HerdrMacVisualAcceptance` compiles the actual Sidebar, DevicePopover, EditDeviceSheet, appearance settings and terminal views into an independent host. It injects an isolated AppModel store and read-state suite and does not start the production AppDelegate, services or remote connection. Screenshots use the native window rectangle after activating the fixture; visually reject any occluded window image. Do not publish full-desktop screenshots or automatic test screen recordings.

Physical test signing may be supplied as ephemeral command overrides (`DEVELOPMENT_TEAM`, automatic signing) rather than changing production signing. Export attachments outside the implementation checkout, review them, then copy only selected native images into `docs/evidence`. Record the source revision, fixture checksum, OS, locale, appearance, Dynamic Type size and actual image dimensions. See the acceptance report for limits and final results.

### Approved chat extension

The visual host also binds its development machine to `https://visual-chat-fixture.invalid/` through an injected ephemeral URLSession/URLProtocol boundary. The literal fixture credential never leaves that boundary. The production service validates the canonical Space/Tab/pane IDs and renders `scene.json`'s conversation in the actual offline WK transcript. No Keychain, Safari storage, remote endpoint or user transcript is read. Fixture preview permits only local networking; no broad native HTTP exception is required.

`reference-capture.mjs` builds no UI of its own. Run it with an already-built public herdr-web-ui checkout and an external output directory. It serves that checkout's actual `dist` on loopback, adapts canonical scene data to the reference's session envelope, and opens a fresh headless Chrome context for each language/theme. Screenshots represent a 390×750 CSS-pixel browser viewport at scale 3, without Safari or iOS chrome. This differs from a 390×844 native iPhone screenshot. The reference's creation button and native bottom app bar differences are explicitly approved scope.

Native keyboard acceptance checks successful real tap/type, visible system keyboard, retained draft, and composer geometry above the keyboard. iOS 26.5's multiline TextField AX `isHittable` can report false while the focused field visibly accepts input; header, drawer and root buttons retain direct `isHittable`/44pt gates.

Color preset fixtures use `VISUAL_THEME=phosphor|amber`, both fixed dark. Old `light`, `dark`, and `system` arguments resolve to Phosphor just like legacy preference migration; they do not expose a third appearance.
