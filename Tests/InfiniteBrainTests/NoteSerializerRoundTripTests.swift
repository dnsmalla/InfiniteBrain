import XCTest
@testable import InfiniteBrainCore

/// Round-trip safety for NoteSerializer across content that has historically
/// broken hand-rolled frontmatter parsers.
final class NoteSerializerRoundTripTests: XCTestCase {

    private func roundTrip(_ note: Note, file: StaticString = #filePath, line: UInt = #line) throws -> Note {
        let text = NoteSerializer.serialize(note)
        return try NoteSerializer.parse(text)
    }

    private func make(title: String = "T", summary: String = "S", body: String,
                      edges: [Edge] = [], sources: [String] = []) -> Note {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return Note(id: "01ID", type: .concept, title: title, summary: summary,
                    body: body, edges: edges, sources: sources,
                    contentHash: "hash", version: 1, createdAt: now, updatedAt: now)
    }

    func testBodyWithHorizontalRulePreserved() throws {
        let body = "Intro paragraph.\n\n---\n\nSection after a horizontal rule."
        let r = try roundTrip(make(body: body))
        XCTAssertEqual(r.body, body, "a `---` in the body must survive round-trip")
    }

    func testBodyWithColonsAndKeyLikeLines() throws {
        let body = "Note: see chapter 3.\ntype: not-a-field\nkey: value"
        let r = try roundTrip(make(body: body))
        XCTAssertEqual(r.body, body)
    }

    func testTitleWithQuotesAndColon() throws {
        let r = try roundTrip(make(title: "He said \"hi\": really", body: "x"))
        XCTAssertEqual(r.title, "He said \"hi\": really")
    }

    func testUnicodeAndEmoji() throws {
        let body = "日本語 — café — 🚀 multi-byte"
        let r = try roundTrip(make(title: "中文标题 🧠", body: body))
        XCTAssertEqual(r.body, body)
        XCTAssertEqual(r.title, "中文标题 🧠")
    }

    func testEdgesRoundTrip() throws {
        let edges = [Edge(type: .relatedTo, target: "01OTHER", evidence: "because: reasons")]
        let r = try roundTrip(make(body: "b", edges: edges))
        XCTAssertEqual(r.edges.count, 1)
        XCTAssertEqual(r.edges[0].target, "01OTHER")
        XCTAssertEqual(r.edges[0].evidence, "because: reasons")
    }

    func testSourcesRoundTrip() throws {
        let r = try roundTrip(make(body: "b", sources: ["01SRC", "02SRC"]))
        XCTAssertEqual(r.sources, ["01SRC", "02SRC"])
    }
}
