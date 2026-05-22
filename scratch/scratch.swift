import Foundation

// Copying DocumentScanner logic to test it
let text = """
Hello world

This is a test.

Table of Contents

Chapter 1

References

Some reference here
"""

let junkPatterns: [String] = [
    "(?m)^Table of Contents\\s*$|(?m)^Contents\\s*$",
    "(?m)^INDEX\\s*$|(?m)^Index\\s*$",
    "(?m)^BIBLIOGRAPHY\\s*$|(?m)^References\\s*$",
    "(?m)^GLOSSARY\\s*$",
    "\\.{5,}\\s*\\d+",
]
let regexes = junkPatterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

let paragraphs = text.components(separatedBy: "\n\n")
var currentRanges: [Range<String.Index>] = []
var currentIndex = text.startIndex

for para in paragraphs {
    let range = text.range(of: para, range: currentIndex..<text.endIndex) ?? currentIndex..<text.endIndex
    let isJunk = regexes.contains { $0.firstMatch(in: text, options: [], range: NSRange(range, in: text)) != nil }
    
    if !isJunk {
        if let last = currentRanges.last, last.upperBound == range.lowerBound {
            currentRanges[currentRanges.count - 1] = last.lowerBound..<range.upperBound
        } else {
            currentRanges.append(range)
        }
    }
    currentIndex = range.upperBound
}

let activeText = currentRanges.map { String(text[$0]) }.joined(separator: "\n\n")
print("activeText length:", activeText.count)
print("ranges length:", currentRanges.count)
