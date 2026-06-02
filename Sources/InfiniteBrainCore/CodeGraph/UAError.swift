import Foundation

public enum UAError: Error, Equatable {
    case binaryMissing
    case nodeVersionTooOld(found: String)
    case folderNotWritable(path: String)
    case runFailed(exitCode: Int32, stderrTail: String)
    case noOutput
    case parseFailed(message: String)
    case unsupportedSchema(version: String)
    case cancelled
}
