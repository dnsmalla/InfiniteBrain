import Foundation
import PDFKit
import Vision
import CoreGraphics

/// Extracts text from a PDF. PDFKit handles text-based PDFs directly. For
/// pages that come back nearly empty (scanned books, image-only pages),
/// falls back to Vision OCR by rasterising the page and recognising text.
public struct PDFExtractor: Sendable {
    public struct Page: Sendable {
        public let number: Int
        public let text: String
        public let usedOCR: Bool
    }

    /// A page with fewer extractable characters than this triggers the OCR
    /// fallback. 50 covers the common scanned-book case (PDFKit returns just
    /// page numbers or empty strings) without false-firing on real text
    /// pages, which usually have 1500+ chars.
    public static let ocrTriggerThreshold = 50

    public init() {}

    public func extract(_ url: URL) throws -> [Page] {
        guard let doc = PDFDocument(url: url) else {
            throw NSError(domain: "PDFExtractor", code: 1)
        }
        var out: [Page] = []
        for i in 0..<doc.pageCount {
            let pdfPage = doc.page(at: i)
            let raw = pdfPage?.string ?? ""
            if raw.count < Self.ocrTriggerThreshold, let p = pdfPage,
               let ocred = Self.ocrPage(p), !ocred.isEmpty {
                out.append(.init(number: i + 1, text: ocred, usedOCR: true))
            } else {
                out.append(.init(number: i + 1, text: raw, usedOCR: false))
            }
        }
        return out
    }

    // MARK: - OCR fallback

    private static func ocrPage(_ page: PDFPage) -> String? {
        let bounds = page.bounds(for: .mediaBox)
        // ~144 DPI gives Vision enough resolution to recognise body text on
        // typical scanned books without exploding memory for huge pages.
        let scale: CGFloat = 2.0
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard let cgImage = renderPage(page, size: size, scale: scale) else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // English by default; expand once we have language detection.
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do { try handler.perform([request]) }
        catch { return nil }

        guard let observations = request.results else { return nil }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    private static func renderPage(_ page: PDFPage, size: CGSize, scale: CGFloat) -> CGImage? {
        guard size.width > 0, size.height > 0,
              let context = CGContext(
                data: nil,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        // White background — scanned PDFs without a fill draw transparently
        // and Vision sees noise.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))

        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)

        return context.makeImage()
    }
}
