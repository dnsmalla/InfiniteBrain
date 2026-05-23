import Foundation

/// Minimal seam for unit testing GraphifyRunner without spawning processes.
public protocol ProcessLauncher: Sendable {
    /// Returns (exitCode, stdoutData, stderrData). Throws on cancellation.
    func run(executable: URL, arguments: [String], environment: [String: String]?) async throws -> (Int32, Data, Data)
}

public struct SystemProcessLauncher: ProcessLauncher {
    public init() {}

    public func run(executable: URL, arguments: [String], environment: [String: String]?) async throws -> (Int32, Data, Data) {
        try await withCheckedThrowingContinuation { cont in
            let proc = Process()
            proc.executableURL = executable
            proc.arguments = arguments
            if let env = environment { proc.environment = env }
            let outPipe = Pipe(); let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe
            proc.terminationHandler = { p in
                let out = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                let err = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                cont.resume(returning: (p.terminationStatus, out ?? Data(), err ?? Data()))
            }
            do { try proc.run() } catch { cont.resume(throwing: error) }
        }
    }
}
