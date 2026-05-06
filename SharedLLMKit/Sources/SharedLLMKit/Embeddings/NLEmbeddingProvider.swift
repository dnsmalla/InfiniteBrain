import Foundation
import NaturalLanguage

/// EmbeddingProvider backed by Apple's NaturalLanguage framework. Free,
/// offline, returns 512-dim sentence embeddings for English. Returns nil if
/// the system model is not yet installed; the orchestrator falls back to an
/// "always add" path in that case.
public struct NLEmbeddingProvider: EmbeddingProvider {
    public let language: NLLanguage
    public init(language: NLLanguage = .english) {
        self.language = language
    }

    public func embed(_ text: String) async throws -> [Float] {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: language) else {
            throw EmbeddingError.modelUnavailable(language: language.rawValue)
        }
        guard let vector = embedding.vector(for: text) else {
            throw EmbeddingError.cannotEmbed(text.prefix(80).description)
        }
        return vector.map(Float.init)
    }
}

public enum EmbeddingError: Error, Equatable {
    case modelUnavailable(language: String)
    case cannotEmbed(String)
}
