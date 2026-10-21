import Foundation

/// Card text split into the pieces it's displayed as: Markdown text (which may hold inline `$math$`),
/// fenced code, `$$display math$$`, and images. Shared by the app and the notification extension.
nonisolated enum CardBlock: Equatable, Sendable {
    case text(String)
    case code(language: String?, code: String)
    case math(String)
    case image(UUID)
}

/// A piece of a text block: Markdown, or inline LaTeX written between single dollar signs.
nonisolated enum InlineSegment: Equatable, Sendable {
    case markdown(String)
    case math(String)
}

nonisolated enum CardContent {
    /// Splits card text into blocks. Code fences (```) are kept verbatim; `$$` math (on its own lines,
    /// or a line holding only `$$…$$`) becomes a display formula; image references become their own
    /// blocks wherever they appear; everything else is Markdown text.
    static func blocks(from text: String) -> [CardBlock] {
        var blocks: [CardBlock] = []
        var textLines: [String] = []
        var code: (language: String?, lines: [String])?
        var math: [String]?

        func flushText() {
            let joined = textLines.joined(separator: "\n")
            textLines = []
            blocks += textAndImages(joined)
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if var open = math {
                if trimmed == "$$" {
                    blocks.append(.math(open.joined(separator: "\n")))
                    math = nil
                } else {
                    open.append(line)
                    math = open
                }
            } else if var open = code {
                if trimmed.hasPrefix("```") {
                    blocks.append(.code(language: open.language, code: open.lines.joined(separator: "\n")))
                    code = nil
                } else {
                    open.lines.append(line)
                    code = open
                }
            } else if trimmed.hasPrefix("```") {
                flushText()
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                code = (language.isEmpty ? nil : language, [])
            } else if trimmed == "$$" {
                flushText()
                math = []
            } else if trimmed.count > 4, trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$") {
                flushText()
                blocks.append(.math(String(trimmed.dropFirst(2).dropLast(2))))
            } else {
                textLines.append(line)
            }
        }
        // An unclosed fence still shows as code, and unclosed math as math.
        if let open = code {
            blocks.append(.code(language: open.language, code: open.lines.joined(separator: "\n")))
        }
        if let open = math {
            blocks.append(.math(open.joined(separator: "\n")))
        }
        flushText()
        return blocks
    }

    private static let reference = /!\[[^\]]*\]\(image:([0-9a-fA-F-]{36})\)/

    /// `$x$`, Pandoc-style so prices don't turn into math: no space just inside the dollars,
    /// no digit right after the closing one, and `\$` is a literal dollar sign.
    private static let inlineMath = /\$(?=[^\s$])([^$\n]*?[^\s\\$])\$(?!\d)/

    /// Splits a text block into Markdown and inline math. Code spans (`like $this$`) aren't math.
    static func inlineSegments(_ text: String) -> [InlineSegment] {
        var segments: [InlineSegment] = []
        var markdown = ""
        var rest = text[...]
        while !rest.isEmpty {
            if rest.hasPrefix("\\$") {
                // An escaped dollar sign stays literal (Markdown drops the backslash).
                markdown += rest.prefix(2)
                rest = rest.dropFirst(2)
            } else if rest.first == "`", let close = rest.dropFirst().firstIndex(of: "`") {
                markdown += rest[...close]
                rest = rest[rest.index(after: close)...]
            } else if let match = rest.prefixMatch(of: inlineMath) {
                if !markdown.isEmpty { segments.append(.markdown(markdown)) }
                markdown = ""
                segments.append(.math(String(match.output.1)))
                rest = rest[match.range.upperBound...]
            } else {
                markdown.append(rest.removeFirst())
            }
        }
        if !markdown.isEmpty { segments.append(.markdown(markdown)) }
        return segments
    }

    private static func textAndImages(_ text: String) -> [CardBlock] {
        var blocks: [CardBlock] = []
        var rest = text[...]
        while let match = rest.firstMatch(of: reference) {
            appendText(String(rest[..<match.range.lowerBound]), to: &blocks)
            if let id = UUID(uuidString: String(match.output.1)) { blocks.append(.image(id)) }
            rest = rest[match.range.upperBound...]
        }
        appendText(String(rest), to: &blocks)
        return blocks
    }

    private static func appendText(_ text: String, to blocks: inout [CardBlock]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { blocks.append(.text(trimmed)) }
    }
}
