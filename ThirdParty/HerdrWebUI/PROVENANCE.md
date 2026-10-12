# herdr-web-ui transcript presentation

Source: https://github.com/devswha/herdr-web-ui/tree/21d1b9208ac489f8690fe8ba758dc5cd73842cf6
MIT, copyright (c) 2026 devswha (LICENSE alongside this file).

Resources/ChatPresentation contains the dependency-free src/lib/markdown.ts scanner,
fileUriPath extracted from src/lib/terminalFileLinks.ts, src/components/ChatView.css,
and the default/light token blocks from src/styles.css. No network or credentials
are included. markdown.js/fileUriPath.js are deterministic type-stripped copies
produced by Node's stripTypeScriptTypes(mode: strip), removing the single parser
import and `export` keywords for classic offline scripts, then trimming trailing
whitespace. Classic scripts are deliberate: WKWebView blocks file-URL ES module
imports. The plainText helper is adapted from ChatView.tsx at this same revision.
The assistant work grouping, initial fold state, tool categories and duration
formatting are adapted from src/lib/workBlocks.ts at the same MIT revision.
The copy glyph uses two CSS boxes matching the reference overlapping-copy icon. Transcript DOM/native bridge
and controller are herdrm implementations. Fonts fall back to the native system
fonts; mathematical notation remains readable source rather than loading a CDN.

The native service schema was separately checked against deployed protocol revision
5d18c535caf042bef69e569aa1f0299072760fde (protocol 22). The renderer assets above
are pinned to 21d1b9208ac489f8690fe8ba758dc5cd73842cf6; these are distinct sources.
