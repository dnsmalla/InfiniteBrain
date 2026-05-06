import Foundation

/// Splits long input into chunks of at most `targetChars` characters,
/// preferring paragraph boundaries, then sentence boundaries, then a hard
/// character split as a last resort. The chunks are passed to `atomize-text`
/// one by one so a 500-page book doesn't blow Claude's context window or
/// silently truncate against `maxTokens` on the response side.
public struct TextChunker: Sendable {
    public init() {}

    public func chunk(_ text: String, targetChars: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, targetChars > 0 else { return [] }

        let paragraphs = trimmed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        var current = ""

        for para in paragraphs {
            if para.count > targetChars {
                // Flush whatever's pending so the giant paragraph starts fresh.
                if !current.isEmpty { chunks.append(current); current = "" }
                chunks.append(contentsOf: splitOversizedParagraph(para, targetChars: targetChars))
                continue
            }
            let separator = current.isEmpty ? "" : "\n\n"
            if current.count + separator.count + para.count <= targetChars {
                current += separator + para
            } else {
                chunks.append(current)
                current = para
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// Split a single oversized paragraph: try sentences, then hard-split.
    private func splitOversizedParagraph(_ para: String, targetChars: Int) -> [String] {
        let sentences = splitIntoSentences(para)

        if sentences.count > 1 {
            var packed: [String] = []
            var current = ""
            for s in sentences {
                if s.count > targetChars {
                    if !current.isEmpty { packed.append(current); current = "" }
                    packed.append(contentsOf: hardSplit(s, targetChars: targetChars))
                    continue
                }
                let separator = current.isEmpty ? "" : " "
                if current.count + separator.count + s.count <= targetChars {
                    current += separator + s
                } else {
                    packed.append(current); current = s
                }
            }
            if !current.isEmpty { packed.append(current) }
            return packed
        }

        return hardSplit(para, targetChars: targetChars)
    }

    /// Sentence-ish splitting that keeps the terminator with the sentence.
    private func splitIntoSentences(_ s: String) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in s {
            current.append(ch)
            if ch == "." || ch == "!" || ch == "?" {
                out.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { out.append(tail) }
        return out.filter { !$0.isEmpty }
    }

    private func hardSplit(_ s: String, targetChars: Int) -> [String] {
        var out: [String] = []
        var i = s.startIndex
        while i < s.endIndex {
            let end = s.index(i, offsetBy: targetChars, limitedBy: s.endIndex) ?? s.endIndex
            out.append(String(s[i..<end]))
            i = end
        }
        return out
    }
}
