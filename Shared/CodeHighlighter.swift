import SwiftUI

/// Light syntax coloring for code blocks: keywords, strings, comments and numbers, for the languages
/// cards are likely to hold. Blocks without a recognized language (```c, ```python, …) stay plain,
/// matching the web app.
nonisolated enum CodeHighlighter {
    private struct Language {
        var keywords: Set<String>
        var lineComments: [String]
        var blockComments = true
    }

    private static let cFamily: Set<String> = [
        "auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else", "enum", "extern",
        "float", "for", "goto", "if", "inline", "int", "long", "register", "return", "short", "signed", "sizeof",
        "static", "struct", "switch", "typedef", "union", "unsigned", "void", "volatile", "while", "bool", "true",
        "false", "NULL", "nullptr", "class", "public", "private", "protected", "virtual", "template", "typename",
        "namespace", "using", "new", "delete", "this", "throw", "try", "catch", "constexpr", "override", "final",
        "uint8_t", "uint16_t", "uint32_t", "uint64_t", "int8_t", "int16_t", "int32_t", "int64_t", "size_t",
    ]

    private static let languages: [String: Language] = {
        let c = Language(keywords: cFamily, lineComments: ["//"])
        let python = Language(
            keywords: [
                "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else",
                "except", "False", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "None",
                "nonlocal", "not", "or", "pass", "raise", "return", "True", "try", "while", "with", "yield", "self",
            ],
            lineComments: ["#"], blockComments: false
        )
        let javascript = Language(
            keywords: [
                "async", "await", "break", "case", "catch", "class", "const", "continue", "default", "delete", "do",
                "else", "export", "extends", "false", "finally", "for", "function", "if", "import", "in", "instanceof",
                "interface", "let", "new", "null", "return", "static", "super", "switch", "this", "throw", "true", "try",
                "type", "typeof", "undefined", "var", "void", "while", "yield", "of", "from",
            ],
            lineComments: ["//"]
        )
        let swift = Language(
            keywords: [
                "actor", "as", "async", "await", "break", "case", "catch", "class", "continue", "default", "defer", "do",
                "else", "enum", "extension", "false", "for", "func", "guard", "if", "import", "in", "init", "is", "let",
                "nil", "private", "protocol", "public", "return", "self", "static", "struct", "switch", "throw", "throws",
                "true", "try", "var", "where", "while", "some", "any",
            ],
            lineComments: ["//"]
        )
        let rust = Language(
            keywords: [
                "as", "break", "const", "continue", "crate", "else", "enum", "false", "fn", "for", "if", "impl", "in",
                "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct",
                "trait", "true", "type", "unsafe", "use", "where", "while", "async", "await",
            ],
            lineComments: ["//"]
        )
        let go = Language(
            keywords: [
                "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for", "func",
                "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select", "struct",
                "switch", "type", "var", "nil", "true", "false",
            ],
            lineComments: ["//"]
        )
        let java = Language(keywords: cFamily.union(["extends", "implements", "import", "package", "super", "interface", "instanceof", "synchronized", "String"]), lineComments: ["//"])
        let shell = Language(
            keywords: ["if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac", "function", "in", "echo", "export", "local", "return"],
            lineComments: ["#"], blockComments: false
        )
        let sql = Language(
            keywords: Set(["select", "from", "where", "join", "inner", "left", "right", "outer", "on", "group", "by", "order", "having",
                           "insert", "into", "values", "update", "set", "delete", "create", "table", "index", "primary", "key",
                           "foreign", "references", "and", "or", "not", "null", "as", "distinct", "limit", "union", "count"]),
            lineComments: ["--"], blockComments: true
        )
        var map: [String: Language] = [:]
        for name in ["c", "h", "cpp", "c++", "cc", "hpp", "cuda", "cu"] { map[name] = c }
        for name in ["python", "py"] { map[name] = python }
        for name in ["javascript", "js", "typescript", "ts", "jsx", "tsx"] { map[name] = javascript }
        for name in ["java", "kotlin", "kt", "csharp", "cs"] { map[name] = java }
        for name in ["bash", "sh", "shell", "zsh"] { map[name] = shell }
        map["swift"] = swift
        map["rust"] = rust
        map["rs"] = rust
        map["go"] = go
        map["sql"] = sql
        return map
    }()

    struct Palette {
        var keyword: Color = .purple
        var string: Color = .red
        var comment: Color = .secondary
        var number: Color = .blue
    }

    static func highlight(_ code: String, language: String?, palette: Palette = Palette()) -> AttributedString {
        var result = AttributedString(code)
        guard let name = language?.lowercased(), let lang = languages[name] else { return result }
        let caseInsensitive = name == "sql"
        let chars = Array(code.unicodeScalars)
        var index = 0

        func color(_ start: Int, _ end: Int, _ color: Color) {
            let lower = result.unicodeScalars.index(result.startIndex, offsetBy: start)
            let upper = result.unicodeScalars.index(lower, offsetBy: end - start)
            result[lower..<upper].foregroundColor = color
        }
        func hasPrefix(_ prefix: String, at position: Int) -> Bool {
            let scalars = Array(prefix.unicodeScalars)
            guard position + scalars.count <= chars.count else { return false }
            return Array(chars[position..<position + scalars.count]) == scalars
        }

        while index < chars.count {
            let char = chars[index]
            if let comment = lang.lineComments.first(where: { hasPrefix($0, at: index) }) {
                var end = index + comment.unicodeScalars.count
                while end < chars.count, chars[end] != "\n" { end += 1 }
                color(index, end, palette.comment)
                index = end
            } else if lang.blockComments, hasPrefix("/*", at: index) {
                var end = index + 2
                while end < chars.count, !hasPrefix("*/", at: end) { end += 1 }
                end = min(end + 2, chars.count)
                color(index, end, palette.comment)
                index = end
            } else if char == "\"" || char == "'" || char == "`" {
                var end = index + 1
                while end < chars.count, chars[end] != char, chars[end] != "\n" {
                    end += chars[end] == "\\" ? 2 : 1
                }
                end = min(end + 1, chars.count)
                color(index, end, palette.string)
                index = end
            } else if CharacterSet.decimalDigits.contains(char), index == 0 || !isWordChar(chars[index - 1]) {
                var end = index
                while end < chars.count, isWordChar(chars[end]) || chars[end] == "." { end += 1 }
                color(index, end, palette.number)
                index = end
            } else if isWordChar(char) {
                var end = index
                while end < chars.count, isWordChar(chars[end]) { end += 1 }
                let word = String(String.UnicodeScalarView(chars[index..<end]))
                if lang.keywords.contains(caseInsensitive ? word.lowercased() : word) { color(index, end, palette.keyword) }
                index = end
            } else {
                index += 1
            }
        }
        return result
    }

    private static func isWordChar(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
    }
}
