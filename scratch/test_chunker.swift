import Foundation

struct Chunk {
    let text: String
    let contextHeader: String?
}

struct SemanticBoundary {
    let range: Range<String.Index>
    let score: Int
    let label: String
}

func findBoundaries(in text: String) -> [SemanticBoundary] {
    var results: [SemanticBoundary] = []
    
    // 1. Headers (High score: 100)
    let headerRegex = try! NSRegularExpression(pattern: "\n{2,}(#{1,6}\\s+.+)", options: [])
    let nsText = text as NSString
    headerRegex.enumerateMatches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
        if let r = match?.range(at: 1), let range = Range(r, in: text) {
            results.append(SemanticBoundary(range: range, score: 100, label: "header"))
        }
    }
    
    return results
}

func chunk(_ text: String, targetChars: Int) -> [Chunk] {
    guard !text.isEmpty, targetChars > 0 else { return [] }
    
    let boundaries = findBoundaries(in: text)
    var chunks: [Chunk] = []
    var startIndex = text.startIndex
    var activeHeader: String? = nil
    
    while startIndex < text.endIndex {
        if let lastHeader = boundaries.filter({ $0.label == "header" && $0.range.lowerBound <= startIndex }).last {
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

let massiveString = String(repeating: "word word word ", count: 20000)
let chunks = chunk(massiveString, targetChars: 16000)
print("count", chunks.count)
