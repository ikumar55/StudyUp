import Foundation
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

    @Test func rejectsFilesThatArentImages() {
        #expect(throws: ImageStore.ImageError.self) {
            try store.save(Data("<html>".utf8), id: UUID())
        }
    }
}
