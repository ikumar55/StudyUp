import Foundation

/// Cloze (fill-in-the-blank) cards, with the same rules as the web app (web/client/src/cloze.ts):
///
///     A {{page fault}} occurs when a page isn't in {{physical memory}}.   → two cards, one per blank
///     {{c1::TCP}} is reliable; {{c1::SCTP}} too; {{c2::UDP}} is not.      → blanks sharing a number hide together
///     The {{TLB::a cache}} holds translations.                             → "[a cache]" is shown as a hint
///
/// Each card's front hides its blank(s) as **[…]**; its back is the whole sentence with the answer in
/// bold. Anything typed as the answer is added below as an extra note.
nonisolated enum Cloze {
    private static let pattern = /\{\{(?:c(\d+)::)?(.+?)(?:::(.+?))?\}\}/

    private struct Deletion {
        let range: Range<String.Index>
        let group: String
        let answer: String
        let hint: String?
    }

    static func hasBlanks(_ text: String) -> Bool {
        text.contains(pattern)
    }

    /// The cards a cloze question makes, in order of first appearance. Empty if there are no blanks.
    static func expand(_ question: String, extra: String = "") -> [(front: String, back: String)] {
        var unnumbered = 0
        let deletions: [Deletion] = question.matches(of: pattern).map { match in
            let group: String
            if let number = match.output.1 {
                group = "c\(number)"
            } else {
                group = "blank\(unnumbered)"
                unnumbered += 1
            }
            return Deletion(
                range: match.range, group: group,
                answer: String(match.output.2).trimmingCharacters(in: .whitespaces),
                hint: match.output.3.map { String($0).trimmingCharacters(in: .whitespaces) }
            )
        }
        var groups: [String] = []
        for deletion in deletions where !groups.contains(deletion.group) {
            groups.append(deletion.group)
        }
        let note = extra.trimmingCharacters(in: .whitespacesAndNewlines)

        return groups.map { group in
            func render(_ hidden: (Deletion) -> String) -> String {
                var text = ""
                var last = question.startIndex
                for deletion in deletions {
                    text += question[last..<deletion.range.lowerBound]
                    text += deletion.group == group ? hidden(deletion) : deletion.answer
                    last = deletion.range.upperBound
                }
                text += question[last...]
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let front = render { "**[\($0.hint ?? "…")]**" }
            let back = render { "**\($0.answer)**" }
            return (front, note.isEmpty ? back : "\(back)\n\n\(note)")
        }
    }
}
