import SwiftUI
import UIKit

/// Card text displayed with its formatting, math, code blocks, and images.
struct CardContentView: View {
    let text: String
    var style: UIFont.TextStyle = .body
    var weight: UIFont.Weight = .regular
    var images: ImageStore = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(CardContent.blocks(from: text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let markdown):
                    RichText(text: markdown, style: style, weight: weight)
                case .math(let latex):
                    MathBlock(latex: latex, style: style)
                case .code(let language, let code):
                    CodeBlock(code: code, language: language)
                case .image(let id):
                    CardImage(id: id, images: images)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CodeBlock: View {
    let code: String
    let language: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(CodeHighlighter.highlight(code, language: language))
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// An image in a card. Tap to view it full screen, where it can be pinched to zoom.
struct CardImage: View {
    let id: UUID
    var images: ImageStore = .shared
    @State private var isZoomed = false

    var body: some View {
        if let url = images.url(for: id), let image = UIImage(contentsOfFile: url.path) {
            Button {
                isZoomed = true
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 360, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Image")
            .accessibilityHint("Shows the image full screen")
            .fullScreenCover(isPresented: $isZoomed) { ZoomedImage(image: image) }
        } else {
            Label("Image not on this iPhone yet. It arrives with the next sync.", systemImage: "photo")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct ZoomedImage: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width * scale, height: geometry.size.height * scale)
                }
                .defaultScrollAnchor(.center)
            }
            .gesture(
                MagnifyGesture()
                    .onChanged { value in scale = min(max(settledScale * value.magnification, 1), 5) }
                    .onEnded { _ in settledScale = scale }
            )
            .onTapGesture(count: 2) {
                withAnimation {
                    scale = scale > 1 ? 1 : 2.5
                    settledScale = scale
                }
            }
            Button("Close Image", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .padding(12)
                .background(.white.opacity(0.15), in: Circle())
                .padding()
        }
    }
}
