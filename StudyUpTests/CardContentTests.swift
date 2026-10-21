import Foundation
import SwiftUI
import Testing
import UIKit
@testable import StudyUp

struct CardContentTests {
    let a = UUID()
    let b = UUID()

    @Test func plainTextIsOneBlock() {
        #expect(CardContent.blocks(from: "A **page fault** is a trap.") == [.text("A **page fault** is a trap.")])
    }

    @Test func splitsTextCodeAndImages() {
        let text = """
        Like this:
        \(ImageStore.snippet(for: a))
        Then call:
        ```c
        int *p = malloc(4);
        ```
        Done.
        """
        #expect(CardContent.blocks(from: text) == [
            .text("Like this:"),
            .image(a),
            .text("Then call:"),
            .code(language: "c", code: "int *p = malloc(4);"),
            .text("Done."),
        ])
    }

    @Test func imagesInsideALineBecomeTheirOwnBlocks() {
        let text = "Before \(ImageStore.snippet(for: a)) between ![](image:\(b.uuidString.uppercased())) after"
        #expect(CardContent.blocks(from: text) == [.text("Before"), .image(a), .text("between"), .image(b), .text("after")])
    }

    @Test func codeKeepsIndentationAndImageLookalikes() {
        let text = "```\n  if x {\n    ![](image:\(a.uuidString))\n  }\n```"
        #expect(CardContent.blocks(from: text) == [.code(language: nil, code: "  if x {\n    ![](image:\(a.uuidString))\n  }")])
    }

    @Test func anUnclosedFenceStillShowsAsCode() {
        #expect(CardContent.blocks(from: "```\nlet x = 1") == [.code(language: nil, code: "let x = 1")])
    }

    @Test func displayMathBlocks() {
        let text = "Softmax:\n$$\n\\sigma(z)_i = \\frac{e^{z_i}}{\\sum_j e^{z_j}}\n$$\nOne line: \n$$x^2$$"
        #expect(CardContent.blocks(from: text) == [
            .text("Softmax:"),
            .math("\\sigma(z)_i = \\frac{e^{z_i}}{\\sum_j e^{z_j}}"),
            .text("One line:"),
            .math("x^2"),
        ])
    }

    @Test func inlineMathSegments() {
        #expect(CardContent.inlineSegments("Scale by $\\frac{1}{\\sqrt{d_k}}$ to keep $x$ small.") == [
            .markdown("Scale by "), .math("\\frac{1}{\\sqrt{d_k}}"), .markdown(" to keep "), .math("x"), .markdown(" small."),
        ])
    }

    @Test func pricesCodeAndEscapesArentMath() {
        #expect(CardContent.inlineSegments("It costs $5 and $10 later") == [.markdown("It costs $5 and $10 later")])
        #expect(CardContent.inlineSegments("Run `echo $HOME$` now") == [.markdown("Run `echo $HOME$` now")])
        #expect(CardContent.inlineSegments("A \\$x\\$ literal") == [.markdown("A \\$x\\$ literal")])
    }

    @Test func referenceHelpers() {
        let text = "Answer\n\(ImageStore.snippet(for: a))"
        #expect(ImageStore.references(in: text) == [a])
        #expect(ImageStore.replacingReferences(in: text) == "Answer\n📷")
        #expect(ImageStore.removingReference(to: a, from: text) == "Answer")
        #expect(ImageStore.appendingReference(to: b, to: "Answer\n") == "Answer\n\(ImageStore.snippet(for: b))")
        #expect(ImageStore.appendingReference(to: b, to: "") == ImageStore.snippet(for: b))
    }
}

struct ImageStoreTests {
    let store = ImageStore(directory: FileManager.default.temporaryDirectory.appending(path: "ImageStoreTests-\(UUID())"))

    private func png(width: CGFloat, height: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @Test func addedImagesAreScaledDownAndStoredAsJPEG() throws {
        let id = try store.add(png(width: 3000, height: 1500))
        let url = try #require(store.url(for: id))
        #expect(url.pathExtension == "jpg")
        let image = try #require(UIImage(contentsOfFile: url.path))
        #expect(image.size.width == 2000)
        #expect(image.size.height == 1000)
        #expect(store.storedIDs() == [id])
    }

    @Test func smallImagesKeepTheirSize() throws {
        let id = try store.add(png(width: 400, height: 300))
        let image = try #require(store.url(for: id).flatMap { UIImage(contentsOfFile: $0.path) })
        #expect(image.size == CGSize(width: 400, height: 300))
    }

    @Test func savedBytesAreKeptAsTheyAre() throws {
        let id = UUID()
        let data = png(width: 10, height: 10)
        try store.save(data, id: id)
        #expect(store.data(for: id)?.data == data)
        #expect(store.data(for: id)?.mime == "image/png")
    }

    @Test func unusedImagesAreRemovedOnceTheyreAWeekOld() throws {
        let used = try store.add(png(width: 10, height: 10))
        let recent = try store.add(png(width: 10, height: 10))
        let old = try store.add(png(width: 10, height: 10))
        let eightDaysAgo = Date.now.addingTimeInterval(-8 * 86_400)
        for id in [used, old] {
            try FileManager.default.setAttributes([.modificationDate: eightDaysAgo], ofItemAtPath: store.url(for: id)!.path)
        }
        #expect(store.removeUnused(referenced: [used]) == 1)
        #expect(store.contains(used))
        #expect(store.contains(recent), "picked recently, maybe for a card not saved yet")
        #expect(!store.contains(old))
    }

    @Test func rejectsFilesThatArentImages() {
        #expect(throws: ImageStore.ImageError.self) {
            try store.save(Data("<html>".utf8), id: UUID())
        }
    }
}

struct ClozeTests {
    @Test func eachBlankBecomesACardShownInContext() {
        let cards = Cloze.expand("A {{page fault}} occurs when a page isn’t in {{physical memory}}.")
        #expect(cards.map(\.front) == [
            "A **[…]** occurs when a page isn’t in physical memory.",
            "A page fault occurs when a page isn’t in **[…]**.",
        ])
        #expect(cards.map(\.back) == [
            "A **page fault** occurs when a page isn’t in physical memory.",
            "A page fault occurs when a page isn’t in **physical memory**.",
        ])
    }

    @Test func numberedBlanksHideTogether() {
        let cards = Cloze.expand("{{c1::TCP}} and {{c1::SCTP}} are reliable; {{c2::UDP}} is not.")
        #expect(cards.map(\.front) == ["**[…]** and **[…]** are reliable; UDP is not.", "TCP and SCTP are reliable; **[…]** is not."])
    }

    @Test func hintsAndExtraNotes() {
        let card = Cloze.expand("The {{TLB::a cache}} holds translations.", extra: "Flushed on a context switch.")[0]
        #expect(card.front == "The **[a cache]** holds translations.")
        #expect(card.back == "The **TLB** holds translations.\n\nFlushed on a context switch.")
    }

    @Test func textWithoutBlanks() {
        #expect(!Cloze.hasBlanks("What is a {page} fault?"))
        #expect(Cloze.expand("No blanks").isEmpty)
    }
}

struct CodeHighlighterTests {
    private func colored(_ text: AttributedString) -> [(String, Bool)] {
        // The highlighter sets SwiftUI colors, so look them up in the SwiftUI attribute scope.
        text.runs.map { (String(text[$0.range].characters), $0[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] != nil) }
    }

    @Test func colorsKeywordsStringsCommentsAndNumbers() {
        let text = CodeHighlighter.highlight("int x = 42; // the answer\nchar *s = \"hi\";", language: "c")
        let runs = colored(text).filter(\.1).map(\.0)
        #expect(runs == ["int", "42", "// the answer", "char", "\"hi\""])
    }

    @Test func unknownLanguagesStayPlain() {
        #expect(colored(CodeHighlighter.highlight("int x = 1", language: nil)).allSatisfy { !$0.1 })
        #expect(colored(CodeHighlighter.highlight("int x = 1", language: "brainfuck")).allSatisfy { !$0.1 })
    }

    @Test func wordsContainingKeywordsAreLeftAlone() {
        let text = CodeHighlighter.highlight("def interface_count(): pass", language: "python")
        #expect(colored(text).filter(\.1).map(\.0) == ["def", "pass"])
    }
}
