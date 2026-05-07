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

    /// Hard cap on how many characters we hand to NLEmbedding. Apple's
    /// `vector(for:)` throws a C++ exception (which becomes a SIGABRT) when
    /// the input is too long. Empirically 1000 is safe; we leave headroom.
    public static let maxInputChars = 800

    public func embed(_ text: String) async throws -> [Float] {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: language) else {
            throw EmbeddingError.modelUnavailable(language: language.rawValue)
        }
        let safe = text.count > Self.maxInputChars
            ? String(text.prefix(Self.maxInputChars))
            : text
        guard let vector = embedding.vector(for: safe) else {
            throw EmbeddingError.cannotEmbed(text.prefix(80).description)
        }
        return vector.map(Float.init)
    }
}

public enum EmbeddingError: Error, Equatable {
    case modelUnavailable(language: String)
    case cannotEmbed(String)
}
