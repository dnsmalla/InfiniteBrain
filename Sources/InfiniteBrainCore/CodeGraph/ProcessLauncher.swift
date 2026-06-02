import Foundation

/// Minimal seam for running and testing external processes.
public protocol ProcessLauncher: Sendable {
    /// Run an executable and await its exit. Honors Task cancellation by
    /// terminating the child process. Returns (exitCode, stdoutData, stderrData).
    /// Throws `CancellationError` if cancelled.
    func run(executable: URL, arguments: [String], environment: [String: String]?) async throws -> (Int32, Data, Data)
}

public struct SystemProcessLauncher: ProcessLauncher {
    public init() {}

    public func run(executable: URL, arguments: [String], environment: [String: String]?) async throws -> (Int32, Data, Data) {
        // Box that's safe to capture into the cancellation handler. The Process
        // is created inside the continuation; we publish it through the box so
        // the cancellation handler can terminate it from another task.
        final class ProcBox: @unchecked Sendable {
            let lock = NSLock()
            var proc: Process?
            var cancelled = false
        }
        let box = ProcBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(Int32, Data, Data), Error>) in
                let proc = Process()
                proc.executableURL = executable
                proc.arguments = arguments
                if let env = environment { proc.environment = env }
                let outPipe = Pipe(); let errPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError = errPipe
                proc.terminationHandler = { p in
                    let out = ((try? outPipe.fileHandleForReading.readToEnd()) ?? nil) ?? Data()
                    let err = ((try? errPipe.fileHandleForReading.readToEnd()) ?? nil) ?? Data()
                    box.lock.lock()
                    let wasCancelled = box.cancelled
                    box.lock.unlock()
                    if wasCancelled {
                        cont.resume(throwing: CancellationError())
                    } else {
                        cont.resume(returning: (p.terminationStatus, out, err))
                    }
                }
                box.lock.lock()
                box.proc = proc
                let alreadyCancelled = box.cancelled
                box.lock.unlock()
                if alreadyCancelled {
                    // Cancellation arrived between handler-install and run; bail out.
                    cont.resume(throwing: CancellationError())
                    return
                }
                do {
                    try proc.run()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        } onCancel: {
            box.lock.lock()
            box.cancelled = true
            let p = box.proc
            box.lock.unlock()
            if let p, p.isRunning { p.terminate() }
        }
    }
}
