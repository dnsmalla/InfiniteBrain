import XCTest
@testable import InfiniteBrainCore

final class EPUBExtractorTests: XCTestCase {
    func testExtractsTextFromMinimalEpub() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let epub = try Self.makeMinimalEpub(at: dir, chapters: [
            ("ch1.xhtml", "<html><body><h1>Chapter 1</h1><p>Hello world.</p></body></html>"),
            ("ch2.xhtml", "<html><body><h1>Chapter 2</h1><p>Second part &amp; tail.</p></body></html>"),
        ])

        let text = try EPUBExtractor().extract(epub)
        XCTAssertTrue(text.contains("Chapter 1"))
        XCTAssertTrue(text.contains("Hello world."))
        XCTAssertTrue(text.contains("Chapter 2"))
        XCTAssertTrue(text.contains("Second part & tail."), "ampersand entity should decode")
    }

    func testStripsScriptsAndStyles() {
        let html = """
        <html><head><style>body { color: red; }</style></head>
        <body>
        <script>alert('no')</script>
        <p>Visible.</p>
        </body></html>
        """
        let stripped = EPUBExtractor.stripHTML(html)
        XCTAssertTrue(stripped.contains("Visible"))
        XCTAssertFalse(stripped.contains("alert"))
        XCTAssertFalse(stripped.contains("color: red"))
    }

    func testDecodesNumericEntities() {
        XCTAssertEqual(EPUBExtractor.decodeEntities("&#65;BC"), "ABC")
        XCTAssertEqual(EPUBExtractor.decodeEntities("&#x4E2D;&#x6587;"), "中文")
    }

    // MARK: - Fixtures

    private static func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ib-epub-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Builds a tiny but spec-conformant EPUB with the given chapters and
    /// returns the path to the resulting .epub file.
    static func makeMinimalEpub(at dir: URL, chapters: [(String, String)]) throws -> URL {
        let stage = dir.appendingPathComponent("stage", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)

        // mimetype must come first, uncompressed; we use `zip -X0` for it.
        try "application/epub+zip".write(
            to: stage.appendingPathComponent("mimetype"),
            atomically: true, encoding: .utf8
        )

        let metaInf = stage.appendingPathComponent("META-INF", isDirectory: true)
        try FileManager.default.createDirectory(at: metaInf, withIntermediateDirectories: true)
        try """
        <?xml version="1.0"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """.write(to: metaInf.appendingPathComponent("container.xml"),
                  atomically: true, encoding: .utf8)

        let oebps = stage.appendingPathComponent("OEBPS", isDirectory: true)
        try FileManager.default.createDirectory(at: oebps, withIntermediateDirectories: true)

        // Write each chapter.
        for (name, html) in chapters {
            try html.write(to: oebps.appendingPathComponent(name),
                           atomically: true, encoding: .utf8)
        }

        // OPF with manifest + spine.
        let manifestItems = chapters.enumerated().map { i, ch in
            "<item id=\"ch\(i)\" href=\"\(ch.0)\" media-type=\"application/xhtml+xml\"/>"
        }.joined(separator: "\n  ")
        let spineItems = chapters.indices.map { i in
            "<itemref idref=\"ch\(i)\"/>"
        }.joined(separator: "\n  ")
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata><dc:title xmlns:dc="http://purl.org/dc/elements/1.1/">Test</dc:title></metadata>
          <manifest>
          \(manifestItems)
          </manifest>
          <spine>
          \(spineItems)
          </spine>
        </package>
        """
        try opf.write(to: oebps.appendingPathComponent("content.opf"),
                      atomically: true, encoding: .utf8)

        // Zip it. We do it the EPUB-spec way: mimetype first, stored, then
        // the rest deflated.
        let epubURL = dir.appendingPathComponent("test.epub")
        try? FileManager.default.removeItem(at: epubURL)

        let zipMime = Process()
        zipMime.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipMime.currentDirectoryURL = stage
        zipMime.arguments = ["-X0", epubURL.path, "mimetype"]
        try zipMime.run()
        zipMime.waitUntilExit()

        let zipRest = Process()
        zipRest.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipRest.currentDirectoryURL = stage
        zipRest.arguments = ["-rDX9", epubURL.path, "META-INF", "OEBPS"]
        try zipRest.run()
        zipRest.waitUntilExit()
        return epubURL
    }
}
