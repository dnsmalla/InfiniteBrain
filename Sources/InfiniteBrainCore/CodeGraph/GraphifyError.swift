import Foundation

public enum GraphifyError: Error, Equatable {
    case binaryMissing
    case runFailed(exitCode: Int32, stderrTail: String)
    case noOutput
    case parseFailed(message: String)
    case unsupportedSchema(version: String)
    case cancelled
}
