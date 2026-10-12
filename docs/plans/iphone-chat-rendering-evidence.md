# iPhone chat presentation evidence (#28)

This module mounts authenticated typed conversation data in a retained **offline**
WKWebView. HTTP credentials, service URLs, and remote page scripts never enter the
renderer. The native shell, composer, terminal transport and service adapter are
separate modules.

## Source and verification boundary

- Implementation started from `cf2de1fa50269f777ae39b4c4f2dc9814ef99bae` in the managed
  `codex/iphone-chat-rendering` worktree. Final verification merged the service and
  `codex/mac-iphone-ui-integration` dependencies.
- Bundled parser/style source: herdr-web-ui MIT revision
  `21d1b9208ac489f8690fe8ba758dc5cd73842cf6`; exact deployed wire schema was checked
  separately against `5d18c535caf042bef69e569aa1f0299072760fde` (protocol 22).
  See `ThirdParty/HerdrWebUI/PROVENANCE.md` and the retained MIT license.
- Hosted tests use an **external HTTP URLProtocol fixture** and actual mounted
  WKWebView pages. They do not mock the controller or renderer internals.
- Dedicated iPhone 13 simulator: `1367A96F-2B8B-4C27-BF4F-2E3DEB330F70`, iOS 26.5.
  These tests do not substitute for the user's iPhone 13 / iOS 18.7.3 acceptance.
- No physical-device operations or authenticated private transcript reads were
  performed by this module's implementation worker.

## Vertical RED/GREEN checks

| Public behavior | Meaningful RED | GREEN |
| --- | --- | --- |
| Actual Markdown page and visible latest reply | Missing renderer API | Mounted headings, prose, list, inline code and fenced code render; actual callback fires |
| Fresh HTTP response still contains old completion | Inverted callback fulfilled for old reply (`herdr-chat-freshness-red-retry.log`) | Old reply cannot clear new completion; changed current reply is presented |
| Multi-part reply viewport | Earlier part falsely proved the latest final part (`herdr-chat-viewport-red.log`) | Last nonempty final part must intersect viewport |
| Distinct turns with identical provider timestamps | Replies collapsed to duplicate second text (`herdr-chat-turn-identity-red.log`) | Disjoint page ordering retains both messages |
| Latest window advances beyond held cursor | Middle reply was missing (`herdr-chat-gap-red.log`) | Exact between-cursor paging fills the gap |
| Final text arrives before native done event | Missing working-edge API (`herdr-chat-working-red.log`) | Known pre-working baseline remains provable after completion |
| Offline page recovery | Missing recovery API (`herdr-chat-reload-red.log`) | Scroll position and open folds recover without cached read proof |
| Cold/current pane verification hook | Missing candidate API (`herdr-chat-candidate-red.log`) | Only still-current visible document can accept native verification; old history rejected |
| Slow image crosses unchanged poll revision | Missing current-ref publication API (`herdr-chat-image-red.log`) | Same key/ref/history publishes; replaced history rejects |
| Copy glyph, clipboard and inert HTML | Missing reference glyph (`herdr-chat-copy-red.log`) | Overlapping copy glyph, real native TXT copy, malicious HTML remains text |
| Retained history cap | Limit notice absent (`herdr-chat-budget-red.log`) | Latest 1000 turns remain and eviction is explicit |
| First completed reply from known empty history | Actual visible reply never acknowledged (`herdr-chat-empty-baseline-red-retry.log`) | Empty baseline retains verified history identity; first new completion is provable |
| Bounded long tool output | Silent clipping (`herdr-chat-tool-limit-red.log`) | Display limit is explicitly stated |

Logs are recorded under `/private/tmp/` with the names above. An initial empty-history
integration build lacked newly merged shell source membership; XcodeGen regeneration
resolved it before the meaningful timeout RED. Simulator-busy and old mixed-log
attempts are excluded from passing evidence.

## Final run

The integrated 13-test run passed with **0 failures** in 8.065 seconds:
`/private/tmp/herdr-chat-final-green.log`; xcresult
`/private/tmp/herdr-chat-render-build/Logs/Test/Test-HerdrMobile-2026.10.11_10-20-17-+0800.xcresult`.
The final integrated **14-test** run, including the explicit long-output notice,
passed with **0 failures** in 8.256 seconds. Log:
`/private/tmp/herdr-chat-final-14-green.log`; xcresult:
`/private/tmp/herdr-chat-render-build/Logs/Test/Test-HerdrMobile-2026.10.11_11-32-26-+0800.xcresult`.

Reproduce after `xcodegen generate`:

```sh
xcodebuild -project HerdrM.xcodeproj -scheme HerdrMobile \
  -destination 'platform=iOS Simulator,id=1367A96F-2B8B-4C27-BF4F-2E3DEB330F70' \
  -derivedDataPath /private/tmp/herdr-chat-render-build \
  -clonedSourcePackagesDirPath /Users/goingta/.codex/worktrees/iphone-device-profiles/herdrm/build-ios/SourcePackages \
  -skipPackagePluginValidation \
  -only-testing:HerdrMobileTests/ChatTranscriptControllerTests \
  -only-testing:HerdrMobileTests/ChatTranscriptRendererTests \
  CODE_SIGNING_ALLOWED=NO test
```

## Retention and freshness behavior

- Foreground + visible + SSH-validated only: two-second polling. Hidden/background
  pauses requests and read acknowledgements while retaining the page and viewport.
- Target/history/document revision and a separate page-process nonce reject stale
  responses and bridge callbacks. A fresh GET or 304 alone does not prove completion.
- Known working-cycle baseline plus changed final reply proves new completion.
  Cold persisted unread requires the shell's independent current native pane check;
  unknown or mismatching evidence conservatively leaves unread unchanged.
- Accumulated turns and display payload are bounded (1000 turns / 8 MiB). Older
  message eviction is explicit. Cursor-gap filling is bounded and resets to fresh
  latest history on an invalid gap instead of retrying an endless cursor chain.
- At most four opaque-reference requests are active per controller. At most four
  loaded images and four full-tool displays remain in a page. Images are byte/pixel
  checked and downsampled to at most 1600 pixels; oversized/unsupported images get
  a retry explanation. Tool displays cap at 500,000 characters with an explicit
  notice to view the remainder on the service.
- WebContent recovery uses the retained document plus bounded native fold/viewport
  context. Automatic recovery is bounded to three attempts per burst; the shell's
  explicit Refresh can retry. The public offline reload path is tested, not an
  artificially forced iOS jetsam event. This does not grant permanent background
  execution or prevent iOS from terminating a process.
- Math remains readable source and animated images use a static downsampled image;
  no CDN/runtime web dependency is introduced.
