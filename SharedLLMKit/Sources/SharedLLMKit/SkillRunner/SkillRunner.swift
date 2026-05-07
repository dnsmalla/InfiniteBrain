import Foundation

public enum SkillRunnerError: Error, Equatable {
    case skillNotFound(String)
    case outputInvalidAfterRetry(lastError: String)
    case hedgingDetected(phrase: String)
}

/// Loads a SKILL.md file, runs it through the configured LLMClient, and
/// validates the output against the declared output schema. Retries once on
/// failure with the validation error appended.
public actor SkillRunner {
    public let client: LLMClient
    public let skillsRoot: URL
    public let validator = SchemaValidator()

    public init(client: LLMClient, skillsRoot: URL) {
        self.client = client
        self.skillsRoot = skillsRoot
    }

    public func run(_ skillName: String, input: [String: Any]) async throws -> [String: Any] {
        let skill = try loadSkill(skillName)
        let system = buildSystemPrompt(skill: skill)
        let rawUser = buildUserPrompt(input: input)
        // Enforce per-skill input budget (token-budget.mdc). 4 chars ≈ 1 token
        // is good enough for English; the model is told the input was clipped
        // so it can produce useful output anyway.
        let userBase = Self.applyBudget(rawUser, cap: skill.manifest.maxInputChars)

        var lastError = ""
        for attempt in 0..<2 {
            let retryHint: String
            if lastError.contains("hedgingDetected") {
                retryHint = "previous output contained hedging boilerplate (\(lastError)). Rewrite without meta-commentary about being an AI or about what the note is doing."
            } else {
                retryHint = "previous output failed validation: \(lastError). Return JSON only, matching the declared output schema exactly."
            }
            let user = attempt == 0 ? userBase : userBase + "\n\nNOTE: \(retryHint)"
            let raw = try await client.complete(system: system, user: user, responseSchema: nil)
            do {
                let parsed = try Self.extractJSON(raw)
                if let outputs = skill.manifest.outputs {
                    try validator.validate(parsed, schema: outputs)
                }
                if let phrase = Self.detectHedging(in: parsed) {
                    throw SkillRunnerError.hedgingDetected(phrase: phrase)
                }
                return parsed
            } catch {
                lastError = String(describing: error)
                continue
            }
        }
        throw SkillRunnerError.outputInvalidAfterRetry(lastError: lastError)
    }

    private func loadSkill(_ name: String) throws -> Skill {
        let url = skillsRoot.appendingPathComponent(name).appendingPathComponent("SKILL.md")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SkillRunnerError.skillNotFound(name)
        }
        return try Skill.parse(at: url)
    }

    private func buildSystemPrompt(skill: Skill) -> String {
        var s = skill.body
        if let outputs = skill.manifest.outputs, !outputs.isEmpty {
            let pairs = outputs.map { "  \"\($0.key)\": <\($0.value)>" }.sorted().joined(separator: ",\n")
            s += "\n\n# Output schema\nReturn a single JSON object matching:\n{\n\(pairs)\n}"
        }
        return s
    }

    private func buildUserPrompt(input: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return "INPUT:\n\(json)\n\nRespond with JSON only."
    }

    /// Walks every string value in the parsed output and returns the first
    /// hedging phrase found, or nil. Per quality-bar.mdc.
    static func detectHedging(in value: Any) -> String? {
        let phrases = [
            "as an ai", "as an a.i.",
            "i cannot help",
            "i can't help",
            "i'm just a",
            "this note discusses",
            "this document discusses",
            "in this note",
            "as a language model",
        ]
        return walkStrings(value) { s in
            let lower = s.lowercased()
            return phrases.first(where: { lower.contains($0) })
        }
    }

    /// Walks `[String: Any]` / `[Any]` / `String`, calling `find` on each
    /// string value. Returns the first non-nil find result.
    private static func walkStrings(_ v: Any, _ find: (String) -> String?) -> String? {
        if let s = v as? String { return find(s) }
        if let dict = v as? [String: Any] {
            for (_, vv) in dict {
                if let hit = walkStrings(vv, find) { return hit }
            }
            return nil
        }
        if let arr = v as? [Any] {
            for item in arr {
                if let hit = walkStrings(item, find) { return hit }
            }
            return nil
        }
        return nil
    }

    /// Truncate the user prompt to `cap` chars, preserving the start (which
    /// usually carries the structural intro like `INPUT:`) and dropping the
    /// tail. The marker tells the model that some content was clipped.
    static func applyBudget(_ user: String, cap: Int?) -> String {
        guard let cap, cap > 0, user.count > cap else { return user }
        let marker = "\n\n[truncated]"
        let keep = max(0, cap - marker.count)
        let head = user.prefix(keep)
        return String(head) + marker
    }

    /// Extracts a JSON object from a model response. Tolerates common
    /// envelopes: surrounding prose, ```json fences, leading/trailing text.
    static func extractJSON(_ text: String) throws -> [String: Any] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip ```json … ``` fence if present.
        var s = trimmed
        if s.hasPrefix("```") {
            if let firstNewline = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: firstNewline)...])
            }
            if let closing = s.range(of: "```", options: .backwards) {
                s = String(s[..<closing.lowerBound])
            }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Find the outermost {...}.
        guard let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}"), start < end else {
            throw NSError(domain: "SkillRunner.extractJSON", code: 1, userInfo: [NSLocalizedDescriptionKey: "no JSON object found"])
        }
        let slice = String(s[start...end])
        guard let data = slice.data(using: .utf8) else {
            throw NSError(domain: "SkillRunner.extractJSON", code: 2)
        }
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = obj as? [String: Any] else {
            throw NSError(domain: "SkillRunner.extractJSON", code: 3, userInfo: [NSLocalizedDescriptionKey: "JSON root is not an object"])
        }
        return dict
    }
}
