import Foundation

/// Card text split into the pieces it's displayed as: Markdown text, fenced code, and images.
nonisolated enum CardBlock: Equatable, Sendable {
    case text(String)
    case code(language: String?, code: String)
    case image(UUID)
}

nonisolated enum CardContent {
    /// Splits card text into blocks. Code fences (```) are kept verbatim; image references become
    /// their own blocks wherever they appear; everything else is Markdown text.
    static func blocks(from text: String) -> [CardBlock] {
        var blocks: [CardBlock] = []
        var textLines: [String] = []
        var code: (language: String?, lines: [String])?

        func flushText() {
            let joined = textLines.joined(separator: "\n")
            textLines = []
            blocks += textAndImages(joined)
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if var open = code {
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
            } else {
                textLines.append(line)
            }
        }
        // An unclosed fence still shows as code.
        if let open = code {
            blocks.append(.code(language: open.language, code: open.lines.joined(separator: "\n")))
        }
        flushText()
        return blocks
    }

    private static let reference = /!\[[^\]]*\]\(image:([0-9a-fA-F-]{36})\)/

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
