import Foundation
import PDFKit

/// Extracts text from a PDF, preserving page boundaries.
public struct PDFExtractor: Sendable {
    public struct Page: Sendable {
        public let number: Int
        public let text: String
    }

    public init() {}

    public func extract(_ url: URL) throws -> [Page] {
        guard let doc = PDFDocument(url: url) else {
            throw NSError(domain: "PDFExtractor", code: 1)
        }
        var out: [Page] = []
        for i in 0..<doc.pageCount {
            let p = doc.page(at: i)
            out.append(.init(number: i + 1, text: p?.string ?? ""))
        }
        return out
    }
}
