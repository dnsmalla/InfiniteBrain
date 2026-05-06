import Foundation

/// Serialises a `Note` to markdown-with-YAML-frontmatter and back. The format
/// is deterministic so byte-equality round-trips are possible (useful for
/// content hashing).
enum NoteSerializer {
    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func serialize(_ note: Note) -> String {
        var fm = "---\n"
        fm += "id: \(quote(note.id))\n"
        fm += "type: \(note.type.rawValue)\n"
        fm += "title: \(quote(note.title))\n"
        fm += "summary: \(quote(note.summary))\n"
        fm += "created_at: \(isoFormatter.string(from: note.createdAt))\n"
        fm += "updated_at: \(isoFormatter.string(from: note.updatedAt))\n"
        fm += "version: \(note.version)\n"
        fm += "content_hash: \(quote(note.contentHash))\n"
        fm += "sources: [\(note.sources.map(quote).joined(separator: ", "))]\n"
        if note.edges.isEmpty {
            fm += "edges: []\n"
        } else {
            fm += "edges:\n"
            for e in note.edges {
                fm += "  - type: \(e.type.rawValue)\n"
                fm += "    target: \(quote(e.target))\n"
                fm += "    evidence: \(quote(e.evidence ?? ""))\n"
            }
        }
        if let s = note.supersededBy {
            fm += "superseded_by: \(quote(s))\n"
        } else {
            fm += "superseded_by: null\n"
        }
        fm += "---\n\n"
        return fm + note.body + (note.body.hasSuffix("\n") ? "" : "\n")
    }

    static func parse(_ content: String) throws -> Note {
        let lines = content.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            throw VaultStoreError.malformed("missing opening frontmatter fence")
        }
        var fmEnd: Int? = nil
        for i in 1..<lines.count where lines[i].trimmingCharacters(in: .whitespaces) == "---" {
            fmEnd = i; break
        }
        guard let end = fmEnd else { throw VaultStoreError.malformed("unterminated frontmatter") }

        let fmLines = Array(lines[1..<end])
        let body = lines[(end + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        var id: String?
        var typeRaw: String?
        var title: String?
        var summary: String?
        var createdAt: Date?
        var updatedAt: Date?
        var version: Int?
        var contentHash: String?
        var sources: [String] = []
        var edges: [Edge] = []
        var supersededBy: String?

        var i = 0
        while i < fmLines.count {
            let line = fmLines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { i += 1; continue }
            // top-level fields have no leading whitespace
            if !line.hasPrefix(" ") && !line.hasPrefix("\t"), let colon = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                switch key {
                case "id":           id = unquote(value)
                case "type":         typeRaw = unquote(value)
                case "title":        title = unquote(value)
                case "summary":      summary = unquote(value)
                case "created_at":   createdAt = isoFormatter.date(from: unquote(value))
                case "updated_at":   updatedAt = isoFormatter.date(from: unquote(value))
                case "version":      version = Int(unquote(value))
                case "content_hash": contentHash = unquote(value)
                case "sources":      sources = parseInlineList(value)
                case "superseded_by":
                    let v = unquote(value)
                    supersededBy = (v == "null" || v.isEmpty) ? nil : v
                case "edges":
                    if value == "[]" { edges = [] }
                    else {
                        // Block-form edges follow as indented `- type: …` items.
                        let (parsed, consumed) = parseEdgeBlock(fmLines, startingAt: i + 1)
                        edges = parsed
                        i = i + 1 + consumed
                        continue
                    }
                default: break
                }
            }
            i += 1
        }

        guard let id, let typeRaw, let type = NodeType(rawValue: typeRaw),
              let title, let summary, let version, let contentHash,
              let createdAt, let updatedAt
        else { throw VaultStoreError.malformed("missing required frontmatter fields") }

        return Note(
            id: id,
            type: type,
            title: title,
            summary: summary,
            body: body,
            edges: edges,
            sources: sources,
            contentHash: contentHash,
            version: version,
            createdAt: createdAt,
            updatedAt: updatedAt,
            supersededBy: supersededBy
        )
    }

    private static func parseEdgeBlock(_ lines: [String], startingAt start: Int) -> (edges: [Edge], consumed: Int) {
        var out: [Edge] = []
        var i = start
        var current: (type: EdgeType, target: String, evidence: String?)? = nil
        func flush() {
            if let c = current { out.append(Edge(type: c.type, target: c.target, evidence: c.evidence)) }
            current = nil
        }
        while i < lines.count {
            let raw = lines[i]
            // Block ends when indentation drops to zero (a new top-level key).
            if !raw.hasPrefix(" ") && !raw.hasPrefix("\t") { break }
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { i += 1; continue }
            if trimmed.hasPrefix("- ") {
                flush()
                let kv = String(trimmed.dropFirst(2))
                if let colon = kv.firstIndex(of: ":") {
                    let k = String(kv[..<colon]).trimmingCharacters(in: .whitespaces)
                    let v = unquote(String(kv[kv.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
                    if k == "type", let t = EdgeType(rawValue: v) {
                        current = (t, "", nil)
                    }
                }
            } else if let colon = trimmed.firstIndex(of: ":") {
                let k = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                let v = unquote(String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
                switch k {
                case "type":
                    if let t = EdgeType(rawValue: v) { current?.type = t }
                case "target":
                    current?.target = v
                case "evidence":
                    current?.evidence = v.isEmpty ? nil : v
                default: break
                }
            }
            i += 1
        }
        flush()
        return (out, i - start)
    }

    private static func parseInlineList(_ value: String) -> [String] {
        var v = value.trimmingCharacters(in: .whitespaces)
        guard v.hasPrefix("[") && v.hasSuffix("]") else { return [] }
        v.removeFirst(); v.removeLast()
        if v.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        return v.split(separator: ",").map { unquote($0.trimmingCharacters(in: .whitespaces)) }
    }

    private static func quote(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
                       .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func unquote(_ s: String) -> String {
        guard s.count >= 2, s.first == "\"", s.last == "\"" else { return s }
        let inner = String(s.dropFirst().dropLast())
        return inner.replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
