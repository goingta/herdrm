import Foundation

/// A live attach must contain actual text from the corresponding pane, rather
/// than a shell/bootstrap/SSH error. Hosts also verify the current generation,
/// foreground visibility, fresh output and a nonblank presented renderer frame.
public enum AttachContentReadiness {
    public static func matchesPane(visibleText: String, paneANSIText: String) -> Bool {
        let plain = paneANSIText
            .replacingOccurrences(of: "\\u001B\\][^\\u0007\\u001B]*(?:\\u0007|\\u001B\\\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\u001B\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
        let viewport = normalized(visibleText)
        guard !viewport.isEmpty else { return false }
        let lines = plain.split(whereSeparator: \.isNewline).map { normalized(String($0)) }.filter { !$0.isEmpty }
        if lines.contains(where: { $0.count >= 8 && viewport.contains($0) }) { return true }
        return !lines.isEmpty && normalized(plain) == viewport
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
