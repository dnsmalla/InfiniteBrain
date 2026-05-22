import Foundation

/// A semantic boundary is a position in the text where a split is likely to 
/// be clean and preserve context.
struct SemanticBoundary {
    let range: Range<String.Index>
    let score: Int
    let label: String
}

public struct Chunk: Sendable {
    public let text: String
    public let contextHeader: String?
}

/// Splits long input into chunks of at most `targetChars` characters,
/// preferring structural boundaries (headers, paragraphs) over hard character
/// limits. "Divide in perfect numbers" means splitting where one logical unit
/// ends and another begins.
public struct TextChunker: Sendable {
    public init() {}

    public func chunk(_ text: String, targetChars: Int) -> [Chunk] {
        guard !text.isEmpty, targetChars > 0 else { return [] }
        
        let boundaries = findBoundaries(in: text)
        var chunks: [Chunk] = []
        var startIndex = text.startIndex
        var activeHeader: String? = nil
        
        while startIndex < text.endIndex {
            // Update active header before picking split point
            // Look for headers that end before or at startIndex
            if let lastHeader = boundaries.filter({ $0.label == "header" && $0.range.lowerBound <= startIndex }).last {
                // Extract header text (remove #s)
                let headerText = String(text[lastHeader.range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                activeHeader = headerText
            }

            let limitIndex = text.index(startIndex, offsetBy: targetChars, limitedBy: text.endIndex) ?? text.endIndex
            if limitIndex == text.endIndex {
                let finalStr = String(text[startIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !finalStr.isEmpty {
                    chunks.append(Chunk(text: finalStr, contextHeader: activeHeader))
                }
                break
            }
            
            // Flex region
            let flexSize = Int(Double(targetChars) * 0.3)
            let flexStart = text.index(limitIndex, offsetBy: -flexSize, limitedBy: startIndex) ?? startIndex
            
            let best = boundaries.filter { $0.range.lowerBound >= flexStart && $0.range.upperBound <= limitIndex }
                .max { a, b in a.score < b.score }
            
            let splitIndex: String.Index
            if let b = best {
                splitIndex = b.range.lowerBound
            } else {
                let searchRange = flexStart..<limitIndex
                if let space = text.rangeOfCharacter(from: .whitespacesAndNewlines, options: .backwards, range: searchRange) {
                    splitIndex = space.lowerBound
                } else {
                    splitIndex = limitIndex
                }
            }
            
            let chunkStr = String(text[startIndex..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunkStr.isEmpty {
                chunks.append(Chunk(text: chunkStr, contextHeader: activeHeader))
            }
            
            startIndex = splitIndex
            while startIndex < text.endIndex, text[startIndex].isWhitespace {
                startIndex = text.index(after: startIndex)
            }
        }
        
        return chunks
    }

    /// Identifies structural markers like headers, horizontal rules, and 
    /// major breaks. High score means "splitting here is very safe".
    private func findBoundaries(in text: String) -> [SemanticBoundary] {
        var results: [SemanticBoundary] = []
        
        // 1. Headers (High score: 100)
        // Match: double-newline + optional #s + space + Title
        // Note: simplified regex for performance
        let headerRegex = try! NSRegularExpression(pattern: "\n{2,}(#{1,6}\\s+.+)", options: [])
        let nsText = text as NSString
        headerRegex.enumerateMatches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            if let r = match?.range(at: 1), let range = Range(r, in: text) {
                results.append(SemanticBoundary(range: range, score: 100, label: "header"))
            }
        }
        
        // 2. Horizontal Rules or Page Breaks (High score: 90)
        let hrRegex = try! NSRegularExpression(pattern: "\n{2,}([-*_=]{3,}\\s*\n)", options: [])
        hrRegex.enumerateMatches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            if let r = match?.range(at: 1), let range = Range(r, in: text) {
                results.append(SemanticBoundary(range: range, score: 90, label: "hr"))
            }
        }
        
        // 3. Paragraph Breaks (Score: 50)
        let paraRegex = try! NSRegularExpression(pattern: "\n{2,}", options: [])
        paraRegex.enumerateMatches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            if let r = match?.range, let range = Range(r, in: text) {
                results.append(SemanticBoundary(range: range, score: 50, label: "paragraph"))
            }
        }
        
        // 4. Sentences (Score: 20)
        // (Rough sentence end: . ! ? followed by space or newline)
        let sentRegex = try! NSRegularExpression(pattern: "[.!?][ \t\n]", options: [])
        sentRegex.enumerateMatches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            if let r = match?.range, let range = Range(r, in: text) {
                results.append(SemanticBoundary(range: range, score: 20, label: "sentence"))
            }
        }
        
        return results
    }
}
