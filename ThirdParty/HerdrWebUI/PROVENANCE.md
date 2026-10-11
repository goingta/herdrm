# herdr-web-ui transcript presentation

Source: https://github.com/devswha/herdr-web-ui/tree/21d1b9208ac489f8690fe8ba758dc5cd73842cf6
MIT, copyright (c) 2026 devswha (LICENSE alongside this file).

Resources/ChatPresentation contains the dependency-free src/lib/markdown.ts scanner,
fileUriPath extracted from src/lib/terminalFileLinks.ts, src/components/ChatView.css,
and the default/light token blocks from src/styles.css. No network or credentials
are included. markdown.js/fileUriPath.js are deterministic type-stripped copies
produced by Node's stripTypeScriptTypes(mode: strip). Transcript DOM/native bridge
and controller are herdrm implementations. Fonts fall back to the native system
fonts; mathematical notation remains readable source rather than loading a CDN.
