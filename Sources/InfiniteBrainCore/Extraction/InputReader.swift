import Foundation

/// Single dispatch point for reading text out of any supported input
/// format. The orchestrator and the wipe / dedup paths all go through
/// here so adding a new format means changing one switch statement.
public enum InputReader {
    public struct Result: Sendable {
        public let text: String
        /// Pages in the source file that needed Vision OCR (PDF only).
        /// 0 for non-PDF inputs.
        public let ocrPages: Int
        /// Total pages reported by the source (PDF only).
        public let totalPages: Int
    }

    public static func read(_ url: URL) throws -> Result {
        switch url.pathExtension.lowercased() {
        case "pdf":
            let pages = try PDFExtractor().extract(url)
            let text = pages.map(\.text).joined(separator: "\n\n")
            return Result(text: text,
                          ocrPages: pages.filter(\.usedOCR).count,
                          totalPages: pages.count)
        case "epub":
            let text = try EPUBExtractor().extract(url)
            return Result(text: text, ocrPages: 0, totalPages: 0)
        default:
            let text = try String(contentsOf: url, encoding: .utf8)
            return Result(text: text, ocrPages: 0, totalPages: 0)
        }
    }
}
