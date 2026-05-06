import Foundation
import Observation

@Observable
public final class IngestViewModel {
    public var droppedFiles: [URL] = []
    public var currentStage: String = "idle"
    public var log: [String] = []

    public init() {}
}
