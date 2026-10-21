import SwiftUI

nonisolated enum DueText {
    /// When a card comes back, in plain words: "again today", "later today", "tomorrow", "in 4 days",
    /// "in 3 weeks", "in 2 months", "in 1.5 years". Minutes and hours don't matter to the person studying:
    /// what matters is whether it's today, and if not, roughly when.
    static func next(_ due: Date, from now: Date = .now, rating: Rating? = nil, calendar: Calendar = .current) -> String {
        if due <= now || calendar.isDate(due, inSameDayAs: now) {
            return rating == .again ? "again today" : "later today"
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
        switch days {
        case ..<2: return "tomorrow"
        case ..<14: return "in \(days) days"
        case ..<60: return "in \(days / 7) weeks"
        case ..<365: return "in \(days / 30) months"
        default:
            let years = (Double(days) / 365 * 10).rounded() / 10
            return years == 1 ? "in 1 year" : "in \(years.formatted()) years"
        }
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
