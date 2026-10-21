import SwiftMath
import SwiftUI
import UIKit

// Text and LaTeX rendering shared by the app and the notification extension.

/// A Markdown text block with inline `$math$`. Formulas are drawn by SwiftMath as template images,
/// so they take the surrounding text color (including in Dark Mode) and sit on the text baseline.
struct RichText: View {
    let text: String
    var style: UIFont.TextStyle = .body
    var weight: UIFont.Weight = .regular
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let font = UIFont.preferredFont(forTextStyle: style).withWeight(weight)
        CardContent.inlineSegments(text).reduce(Text("")) { result, segment in
            switch segment {
            case .markdown(let markdown):
                return Text("\(result)\(Text(MarkdownRendering.attributed(markdown)))")
            case .math(let latex):
                guard let rendered = MathRenderer.image(latex: latex, fontSize: font.pointSize, display: false) else {
                    return Text("\(result)\(Text("$\(latex)$").foregroundStyle(.red))")
                }
                let image = Text(Image(uiImage: rendered.image).renderingMode(.template)).baselineOffset(-rendered.descent)
                return Text("\(result)\(image)")
            }
        }
        .font(Font(font))
        .id(dynamicTypeSize)
    }
}

/// A `$$display$$` formula, centered, scrolling sideways if it's wider than the screen.
struct MathBlock: View {
    let latex: String
    var style: UIFont.TextStyle = .body

    var body: some View {
        let fontSize = UIFont.preferredFont(forTextStyle: style).pointSize * 1.1
        if let rendered = MathRenderer.image(latex: latex, fontSize: fontSize, display: true) {
            let formula = Image(uiImage: rendered.image)
                .renderingMode(.template)
                .padding(.vertical, 4)
            // Centered when it fits, like the web app; otherwise it scrolls sideways.
            ViewThatFits(in: .horizontal) {
                formula.frame(maxWidth: .infinity)
                ScrollView(.horizontal, showsIndicators: false) { formula }
            }
            .accessibilityLabel(latex)
        } else {
            Text("$$\(latex)$$")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.red)
        }
    }
}

enum MathRenderer {
    struct Rendered {
        let image: UIImage
        let descent: CGFloat
    }

    private final class Box {
        let rendered: Rendered
        init(_ rendered: Rendered) { self.rendered = rendered }
    }

    private static let cache = NSCache<NSString, Box>()

    /// Draws LaTeX once per (formula, size, mode) and reuses it; returns nil for LaTeX SwiftMath can't parse.
    static func image(latex: String, fontSize: CGFloat, display: Bool) -> Rendered? {
        let key = "\(display ? "D" : "T")\(fontSize)|\(latex)" as NSString
        if let cached = cache.object(forKey: key) { return cached.rendered }
        var math = MathImage(
            latex: latex, fontSize: fontSize, textColor: .black,
            labelMode: display ? .display : .text, textAlignment: .left
        )
        let (error, image, layout) = math.asImage()
        guard error == nil, let image else { return nil }
        let rendered = Rendered(image: image.withRenderingMode(.alwaysTemplate), descent: layout?.descent ?? 0)
        cache.setObject(Box(rendered), forKey: key)
        return rendered
    }
}

enum MarkdownRendering {
    /// Inline Markdown (**bold**, *italic*, `code`, links), keeping line breaks.
    static func attributed(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }
}

extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        guard weight != .regular else { return self }
        let descriptor = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
