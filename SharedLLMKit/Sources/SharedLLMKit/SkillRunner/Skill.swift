import Foundation

public enum SkillParseError: Error, Equatable {
    case missingFrontmatter
    case unterminatedFrontmatter
    case missingRequiredField(String)
}

/// Parsed representation of a SKILL.md file. The frontmatter declares the
/// skill's name, description, model, and input/output schemas; the body is the
/// system prompt.
public struct Skill: Sendable, Equatable {
    public struct Manifest: Codable, Sendable, Equatable {
        public var name: String
        public var description: String
        public var model: String?
        public var inputs: [String: String]?      // field → simple type tag
        public var outputs: [String: String]?
    }

    public let manifest: Manifest
    public let body: String
    public let sourceURL: URL?

    public init(manifest: Manifest, body: String, sourceURL: URL? = nil) {
        self.manifest = manifest
        self.body = body
        self.sourceURL = sourceURL
    }

    public static func parse(at url: URL) throws -> Skill {
        let content = try String(contentsOf: url, encoding: .utf8)
        var skill = try parse(content: content)
        skill = Skill(manifest: skill.manifest, body: skill.body, sourceURL: url)
        return skill
    }

    public static func parse(content: String) throws -> Skill {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            throw SkillParseError.missingFrontmatter
        }

        var fmEnd: Int? = nil
        for i in 1..<lines.count where lines[i].trimmingCharacters(in: .whitespaces) == "---" {
            fmEnd = i
            break
        }
        guard let end = fmEnd else { throw SkillParseError.unterminatedFrontmatter }

        let fmLines = Array(lines[1..<end])
        let bodyLines = Array(lines[(end + 1)...])
        let body = bodyLines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let manifest = try parseFrontmatter(lines: fmLines)
        return Skill(manifest: manifest, body: body)
    }

    /// Minimal YAML-subset parser:
    /// - top-level `key: value`
    /// - top-level `key:` followed by indented `  subkey: value` lines (becomes a [String:String] map)
    /// - inline `# comment` is stripped
    private static func parseFrontmatter(lines: [String]) throws -> Manifest {
        var name: String?
        var description: String?
        var model: String?
        var inputs: [String: String]?
        var outputs: [String: String]?

        var i = 0
        while i < lines.count {
            let raw = lines[i]
            let stripped = stripComment(raw)
            if stripped.trimmingCharacters(in: .whitespaces).isEmpty { i += 1; continue }
            // top-level lines have no leading whitespace
            guard !raw.hasPrefix(" ") && !raw.hasPrefix("\t") else { i += 1; continue }
            guard let colon = stripped.firstIndex(of: ":") else { i += 1; continue }
            let key = String(stripped[..<colon]).trimmingCharacters(in: .whitespaces)
            let valuePart = String(stripped[stripped.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)

            if valuePart.isEmpty {
                // nested map follows
                var map: [String: String] = [:]
                i += 1
                while i < lines.count {
                    let sub = lines[i]
                    if !sub.hasPrefix(" ") && !sub.hasPrefix("\t") { break }
                    let subStripped = stripComment(sub).trimmingCharacters(in: .whitespaces)
                    if subStripped.isEmpty { i += 1; continue }
                    if let c = subStripped.firstIndex(of: ":") {
                        let k = String(subStripped[..<c]).trimmingCharacters(in: .whitespaces)
                        let v = String(subStripped[subStripped.index(after: c)...])
                            .trimmingCharacters(in: .whitespaces)
                        map[k] = unquote(v)
                    }
                    i += 1
                }
                switch key {
                case "inputs":  inputs  = map
                case "outputs": outputs = map
                default: break
                }
                continue
            }

            let v = unquote(valuePart)
            switch key {
            case "name":        name = v
            case "description": description = v
            case "model":       model = v
            default: break
            }
            i += 1
        }

        guard let name else { throw SkillParseError.missingRequiredField("name") }
        guard let description else { throw SkillParseError.missingRequiredField("description") }

        return Manifest(name: name, description: description, model: model, inputs: inputs, outputs: outputs)
    }

    private static func stripComment(_ line: String) -> String {
        // strip ` # comment` but NOT `#` flush-left (which doesn't appear in valid YAML anyway)
        guard let hashIdx = line.firstIndex(of: "#") else { return line }
        if hashIdx == line.startIndex { return line }
        let before = line.index(before: hashIdx)
        if line[before] == " " || line[before] == "\t" {
            return String(line[..<hashIdx])
        }
        return line
    }

    private static func unquote(_ s: String) -> String {
        guard s.count >= 2 else { return s }
        let first = s.first!
        let last = s.last!
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(s.dropFirst().dropLast())
        }
        return s
    }
}
