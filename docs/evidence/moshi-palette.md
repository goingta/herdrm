# Green, black and white palette evidence

2026-10-11. Reference: the user's Moshi screenshot in this conversation. These are herdrm's own color values inspired by that attachment, not verified official Moshi tokens. The private reference screenshot is not copied into this repository.

## Scope and source

Source checkpoint: `eaf07c7dd26315a335e3ce419969d090836b081a`, baseline `275daf734a2be07a000e12820fb11864acc8fbb1`. Review correction `e93f80c512a0734dcb4119898f0d79b4b4da15fe` replaces Chat Service Form's independent amber tint with the shared accent. Native/WK warm-color audit leaves only deliberately preserved brand, ANSI/syntax, semantic status and device-identity colors.

`AppPalette` supplies neutral surfaces and emphasis colors to shared native `Theme`, the mobile reference adapter and both Ghostty runtimes. The offline WK transcript mirrors these values in its existing CSS tokens. Dark content is black, panels `#111214`, input/elevated surfaces `#1B1C1E`, text `#F5F5F7`, dim text `#A1A1AA`, and emphasis `#00F000`. Light content is white with neutral gray surfaces and `#006B12` emphasis text. Primary buttons use `#00F000` with black labels in both appearances.

Typography, Dynamic Type, layout, hit areas, logo shape, application icon assets, ANSI colors, Agent brand colors, blue unread state and warning/status colors are unchanged. Mac keeps its current native sidebar material and layout. External project webpages retain their own styles. Formal `project.yml`, Info.plist, SSH and key configuration are unchanged; ad-hoc signing flags were supplied only to verification commands.

Before this color request, the user answered “三项都正常” for the three physical iPhone fixes (Git branch subtitle, outside-tap keyboard dismissal, mobile typography). That acceptance does not establish completion of every real service/chat/attachment flow. This palette has Simulator evidence below; physical iPhone palette acceptance remains pending.

## Validation

- Formal `HerdrM` macOS build: **BUILD SUCCEEDED**, `/private/tmp/herdr-moshi-mac-build.log`.
- Formal `HerdrMobile` iOS Simulator build: **BUILD SUCCEEDED**, `/private/tmp/herdr-moshi-ios-build.log`.
- Existing actual UI tests in `HerdrNavigationAcceptance`: **2 tests, 0 failures**, 185.419 seconds; `/private/tmp/herdr-moshi-visual-final.log`.
  - `testRenderedLanguageThemeMatrixAndPreviewDraftRoundTrip`: English/Chinese × light/dark; actual transcript folding, drawer, mode controls, draft input and keyboard geometry, device forms, local preview navigation/round trip and actual Ghostty rendering.
  - `testActualReferenceChatRendersCanonicalConversation`: canonical transcript folds/expands/recloses through the rendered WK page.

Result bundle: `/private/tmp/herdr-moshi-dd/Logs/Test/Test-HerdrNavigationAcceptance-2026.10.11_21-30-21-+0800.xcresult`. This is one final batch of two tests, not eight additional tests. Existing tests were reused for a reversible color change; no tests mirroring palette constants were added.

After the review correction, the focused actual control workflow `testChatServiceSheetAppearanceAndCancelPreservesWorkspace` passed: **1 test, 0 failures**, 21.799 seconds, `/private/tmp/herdr-moshi-chat-sheet.log`. It opens the real More → Chat Service sheet in light/dark, checks the fixture address and accessible action, cancels and checks the selected Tab/composer remain available. It performs no authentication/save/remove. Its result bundle is `/private/tmp/herdr-moshi-dd/Logs/Test/Test-HerdrNavigationAcceptance-2026.10.11_21-37-30-+0800.xcresult`. The full matrix was not repeated for this isolated tint fix.

All captures use the existing synthetic fixture, including `fixture.invalid`, local HTTP preview and injected terminal bytes. No business Agent prompts, live SSH mutations or private keys are involved. Screenshot hashes, scene hash and original attachment names are in [the manifest](moshi-palette/manifest.json). Captures are unmodified raw 1170×2532 PNGs from an iPhone 13 Simulator (390×844 points, iOS 26.5).

## Inspected screenshots

| Page | Light | Dark |
| --- | --- | --- |
| English chat | [PNG](moshi-palette/chat-en-light.png) | [PNG](moshi-palette/chat-en-dark.png) |
| Chinese chat | [PNG](moshi-palette/chat-zh-light.png) | [PNG](moshi-palette/chat-zh-dark.png) |
| Draft and keyboard | [PNG](moshi-palette/keyboard-zh-light.png) | [PNG](moshi-palette/keyboard-zh-dark.png) |
| Actual Ghostty renderer | [PNG](moshi-palette/ghostty-zh-light.png) | [PNG](moshi-palette/ghostty-zh-dark.png) |
| Chat Service sheet | [PNG](moshi-palette/chat-service-en-light.png) | [PNG](moshi-palette/chat-service-en-dark.png) |

[Dark drawer](moshi-palette/sidebar-zh-dark.png) shows the branch subtitle, selected neutral surface, green close action and unchanged status colors. Chat captures show matching native/WK neutral surfaces, green Tab underline and controls, readable black primary-button arrows, and original Claude branding. Ghostty captures show white/black content, appearance-specific green cursor and preserved ANSI red/green/blue. The isolated Ghostty scene verifies the renderer; it is not an additional screenshot of a live SSH session. Mac build/source verification is recorded above; this batch did not capture a new Mac screenshot.

The inspected Chat Service sheet uses green Cancel, picker and sign-in actions, keeps its existing system Form surfaces, disabled Save styling and red destructive action.

## Contrast calculation

Relative sRGB luminance calculation (`0.2126 R + 0.7152 G + 0.0722 B` after linearization, `(Lhigh + 0.05)/(Llow + 0.05)`) gives these nominal opaque-color ratios. This is a palette check, not certification of every rendered state.

| Pair | Ratio |
| --- | --- |
| Black primary text / `#00F000` | 13.46:1 |
| Dark text `#F5F5F7` / black | 19.29:1 |
| Dark dim `#A1A1AA` / input `#1B1C1E` | 6.65:1 |
| Light accent `#006B12` / white | 6.75:1 |
| Light text `#171719` / white | 17.90:1 |
| Light dim `#52525B` / panel `#F5F5F7` | 7.10:1 |
| Dark terminal text / selection `#153D18` | 11.26:1 |
| Light terminal text / selection `#D0F4D0` | 14.95:1 |
