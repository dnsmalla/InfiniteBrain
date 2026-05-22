import Foundation
import SharedLLMKit

public struct DraftSection: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public var title: String
    public var content: String
    public var customPrompt: String?
    public var selectedCitationIds: [String]
    public var actualCitedIds: [String]
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        content: String = "",
        customPrompt: String? = nil,
        selectedCitationIds: [String] = [],
        actualCitedIds: [String] = []
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.customPrompt = customPrompt
        self.selectedCitationIds = selectedCitationIds
        self.actualCitedIds = actualCitedIds
    }
}

public struct DraftingSession: Sendable, Equatable, Codable {
    public var topic: String
    public var template: String
    public var sections: [DraftSection]
    public var globalCitationIds: [String]
    
    public init(topic: String, template: String, sections: [DraftSection] = [], globalCitationIds: [String] = []) {
        self.topic = topic
        self.template = template
        self.sections = sections
        self.globalCitationIds = globalCitationIds
    }
}

public actor DraftingService {
    private let skillRunner: SkillRunner
    private let fallbackRunner: SkillRunner?
    private let store: VaultStore
    private let embeddings: EmbeddingProvider
    private let index: EmbeddingIndex
    private let onUsage: UsageHandler?

    public init(
        skillRunner: SkillRunner,
        fallbackRunner: SkillRunner? = nil,
        store: VaultStore,
        embeddings: EmbeddingProvider,
        index: EmbeddingIndex,
        onUsage: UsageHandler? = nil
    ) {
        self.skillRunner = skillRunner
        self.fallbackRunner = fallbackRunner
        self.store = store
        self.embeddings = embeddings
        self.index = index
        self.onUsage = onUsage
    }
    
    private func runSkill(_ name: String, input: [String: Any]) async throws -> [String: Any] {
        do {
            return try await skillRunner.run(name, input: input, onUsage: onUsage)
        } catch {
            let errString = "\(error)"
            let skillsPath = await skillRunner.skillsRoot.path
            let fallbackPath = await fallbackRunner?.skillsRoot.path ?? "none"
            
            if (errString.contains("skillNotFound") || errString.contains("error 0")), let fallback = fallbackRunner {
                do {
                    return try await fallback.run(name, input: input, onUsage: onUsage)
                } catch {
                    throw NSError(domain: "Drafting", code: 0, userInfo: [NSLocalizedDescriptionKey: "Skill \(name) not found. Checked: \(skillsPath) and \(fallbackPath). Error: \(error)"])
                }
            }
            throw error
        }
    }

    /// PHASE 1: Plan the outline based on the topic and template.
    public func planOutline(topic: String, template: String) async throws -> [DraftSection] {
        let result = try await runSkill(
            "plan-draft-outline",
            input: [
                "topic": topic,
                "template_name": template
            ]
        )
        
        let titles = (result["sections"] as? [String]) ?? []
        return titles.map { DraftSection(title: $0) }
    }

    /// PHASE 2: Generate content for a specific section.
    public func generateSection(
        _ section: DraftSection,
        in session: DraftingSession
    ) async throws -> (content: String, citedIds: [String]) {
        
        // 1. Gather context. Use specifically selected IDs if present, otherwise auto-retrieve.
        var contextNotes: [[String: Any]] = []
        let idsToLoad = section.selectedCitationIds.isEmpty 
            ? try await autoRetrieveIds(for: "\(session.topic): \(section.title)")
            : section.selectedCitationIds
            
        for id in idsToLoad.prefix(10) {
            if let note = try? await store.read(id: id) {
                contextNotes.append([
                    "id": note.id,
                    "title": note.title,
                    "body": note.body,
                    "type": note.type.rawValue
                ])
            }
        }
        
        // 2. Run the specialized drafting skill
        let result = try await runSkill(
            "draft-section",
            input: [
                "topic": session.topic,
                "section_title": section.title,
                "instruction": section.customPrompt ?? "",
                "notes": contextNotes,
                "previous_sections": session.sections.filter { !$0.content.isEmpty }.map { ["title": $0.title, "content": $0.content.prefix(500)] }
            ]
        )
        
        return (
            content: (result["content"] as? String) ?? "",
            citedIds: (result["cited_ids"] as? [String]) ?? []
        )
    }
    
    private func autoRetrieveIds(for query: String) async throws -> [String] {
        let v = try await embeddings.embed(query)
        let hits = await index.nearest(to: v, k: 10)
        return hits.map { $0.id }
    }

    // Legacy support for single-shot (v1)
    public func compose(topic: String, template: String) async throws -> Draft {
        let sections = try await planOutline(topic: topic, template: template)
        var session = DraftingSession(topic: topic, template: template, sections: sections)
        
        var fullText = ""
        var allCitations: Set<String> = []
        
        for i in 0..<session.sections.count {
            let res = try await generateSection(session.sections[i], in: session)
            session.sections[i].content = res.content
            fullText += "## \(session.sections[i].title)\n\n\(res.content)\n\n"
            allCitations.formUnion(res.citedIds)
        }
        
        return Draft(text: fullText, citedIds: Array(allCitations), templateUsed: template)
    }
}

public struct Draft: Sendable, Equatable {
    public let text: String
    public let citedIds: [String]
    public let templateUsed: String
}
