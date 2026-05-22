import XCTest
@testable import InfiniteBrainCore

final class TextChunkerTests: XCTestCase {
    let chunker = TextChunker()

    func testShortInputProducesOneChunk() {
        let chunks = chunker.chunk("hello world", targetChars: 1_000)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].text, "hello world")
    }

    func testEmptyInputProducesNoChunks() {
        XCTAssertTrue(chunker.chunk("", targetChars: 100).isEmpty)
        XCTAssertTrue(chunker.chunk("   \n\n  ", targetChars: 100).isEmpty)
    }

    func testPacksParagraphsUntilTarget() {
        let p1 = String(repeating: "a", count: 80)  // 80
        let p2 = String(repeating: "b", count: 80)  // 80
        let p3 = String(repeating: "c", count: 80)  // 80
        let text = "\(p1)\n\n\(p2)\n\n\(p3)"          // 80+2+80+2+80 = 244
        let chunks = chunker.chunk(text, targetChars: 200)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertTrue(chunks[0].text.contains(p1))
        XCTAssertTrue(chunks[0].text.contains(p2))
        XCTAssertFalse(chunks[0].text.contains(p3))
        XCTAssertTrue(chunks[1].text.contains(p3))
    }

    func testSplitsParagraphLargerThanTarget() {
        // One paragraph longer than the target — must be split, not dropped.
        let huge = String(repeating: "x", count: 1_000)
        let chunks = chunker.chunk(huge, targetChars: 300)
        XCTAssertGreaterThan(chunks.count, 1)
        for c in chunks {
            XCTAssertLessThanOrEqual(c.text.count, 330) // allowed a bit of flex
        }
        XCTAssertEqual(chunks.map(\.text).joined().count, huge.count)
    }

    func testPrefersSentenceBoundariesWithinALongParagraph() {
        let s1 = "First sentence describes the issue. "
        let s2 = "Second sentence elaborates in detail. "
        let s3 = "Third sentence proposes a path."
        let para = s1 + s2 + s3
        let chunks = chunker.chunk(para, targetChars: 100)
        XCTAssertGreaterThan(chunks.count, 1)
        for c in chunks {
            let trimmed = c.text.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertTrue(["!", ".", "?"].contains(where: trimmed.hasSuffix)
                          || c.text == chunks.last?.text)
        }
    }

    func testCapturesActiveHeader() {
        let text = "# Intro\n\nParagraph 1.\n\n## Section\n\nParagraph 2."
        let chunks = chunker.chunk(text, targetChars: 20)
        XCTAssertGreaterThanOrEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].contextHeader, "Intro")
        if let last = chunks.last {
            XCTAssertEqual(last.contextHeader, "Section")
        }
    }
}
