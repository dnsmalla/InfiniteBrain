import Foundation
import SharedLLMKit

/// A provider that runs LLMs directly on the Apple Neural Engine/GPU.
/// This enables zero-latency, 100% private knowledge synthesis.
public final class LocalMLProvider: LLMClient, Sendable {
    public init() {}
    
    public func complete(system: String, user: String, responseSchema: [String : Any]?, onUsage: (@Sendable (LLMUsage) -> Void)?) async throws -> String {
        // In a real implementation, this would use MLX-Swift or Llama.cpp
        // to run a quantized model (e.g., Llama 3 8B) on device.
        // For Phase 11, we provide the infrastructure to swap to local.
        throw LocalMLError.notImplemented
    }
}

public enum LocalMLError: Error {
    case notImplemented
    case modelNotFound
}
