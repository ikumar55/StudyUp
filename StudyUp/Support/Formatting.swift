import SwiftUI

nonisolated enum IntervalText {
    /// Compact interval label: "<1m", "10m", "3h", "4d", "2.5mo", "1.3y".
    static func short(_ interval: TimeInterval) -> String {
        let minutes = interval / 60
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(Int(minutes.rounded()))m" }
        let hours = minutes / 60
        if hours < 24 { return "\(Int(hours.rounded()))h" }
        let days = hours / 24
        if days < 30 { return "\(Int(days.rounded()))d" }
        if days < 365 { return String(format: "%.1fmo", days / 30) }
        return String(format: "%.1fy", days / 365)
    }
}

nonisolated enum PlainText {
    /// Strips inline Markdown for places that can't render it, like notifications.
    static func from(markdown: String) -> String {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let attributed = try? AttributedString(markdown: markdown, options: options) else { return markdown }
        return String(attributed.characters)
    }
}

/// Renders inline Markdown (**bold**, *italic*, `code`, links) and keeps line breaks.
struct MarkdownText: View {
    let source: String

    init(_ source: String) {
        self.source = source
    }

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }
}
