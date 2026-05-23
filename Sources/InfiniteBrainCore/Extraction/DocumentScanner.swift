import Foundation

public struct ScanResults: Sendable {
    public let activeRanges: [Range<String.Index>]
    public let skippedCount: Int
}

/// A lightweight scanner that identifies regions of a document to process 
/// vs regions to skip (ToC, Index, Bib). This ensures we "divide in perfect 
/// numbers" by only focusing on substantive content.
public struct DocumentScanner: Sendable {
    public init() {}
    
    public func scan(_ text: String) -> ScanResults {
        var skippedCount = 0
        let nsText = text as NSString
        
        let junkPatterns: [String] = [
            "(?m)^Table of Contents\\s*$|(?m)^Contents\\s*$",
            "(?m)^INDEX\\s*$|(?m)^Index\\s*$",
            "(?m)^BIBLIOGRAPHY\\s*$|(?m)^References\\s*$",
            "(?m)^GLOSSARY\\s*$",
            "\\.{5,}\\s*\\d+",
        ]
        let regexes = junkPatterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
        
        var segments: [(String, NSRange)] = []
        let regex = try! NSRegularExpression(pattern: "\n\n", options: [])
        var lastIndex = 0
        
        regex.enumerateMatches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            if let m = match {
                let range = NSRange(location: lastIndex, length: m.range.location - lastIndex)
                segments.append((nsText.substring(with: range), range))
                lastIndex = m.range.location + m.range.length
            }
        }
        let lastRange = NSRange(location: lastIndex, length: nsText.length - lastIndex)
        segments.append((nsText.substring(with: lastRange), lastRange))

        var currentRanges: [Range<String.Index>] = []
        for (para, nsRange) in segments {
            if para.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            let isJunk = regexes.contains { $0.firstMatch(in: text, options: [], range: nsRange) != nil }
            if !isJunk {
                if let range = Range(nsRange, in: text) {
                    currentRanges.append(range)
                }
            } else {
                skippedCount += 1
            }
        }
        return ScanResults(activeRanges: currentRanges, skippedCount: skippedCount)
    }
}
