import XCTest
@testable import InfiniteBrainCore

final class TextChunkerTests: XCTestCase {
    let chunker = TextChunker()

    func testShortInputProducesOneChunk() {
        let chunks = chunker.chunk("hello world", targetChars: 1_000)
        XCTAssertEqual(chunks, ["hello world"])
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
        XCTAssertTrue(chunks[0].contains(p1))
        XCTAssertTrue(chunks[0].contains(p2))
        XCTAssertFalse(chunks[0].contains(p3))
        XCTAssertTrue(chunks[1].contains(p3))
    }

    func testSplitsParagraphLargerThanTarget() {
        // One paragraph longer than the target — must be split, not dropped.
        let huge = String(repeating: "x", count: 1_000)
        let chunks = chunker.chunk(huge, targetChars: 200)
        XCTAssertGreaterThan(chunks.count, 1)
        for c in chunks {
            XCTAssertLessThanOrEqual(c.count, 200)
        }
        XCTAssertEqual(chunks.joined().count, huge.count)
    }

    func testPrefersSentenceBoundariesWithinALongParagraph() {
        // Three sentences, total ~270 chars. Target 150 → splits between sentences,
        // never mid-sentence.
        let s1 = "First sentence describes the issue clearly. "  // ~45
        let s2 = "Second sentence elaborates the consequences in detail and reasoning. "  // ~70
        let s3 = "Third sentence proposes a path forward."  // ~40
        let para = s1 + s2 + s3
        let chunks = chunker.chunk(para, targetChars: 100)
        XCTAssertGreaterThan(chunks.count, 1)
        for c in chunks {
            // Each chunk should end with a terminator (or be the whole thing).
            let trimmed = c.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertTrue(["!", ".", "?"].contains(where: trimmed.hasSuffix)
                          || c == chunks.last)
        }
    }
}
