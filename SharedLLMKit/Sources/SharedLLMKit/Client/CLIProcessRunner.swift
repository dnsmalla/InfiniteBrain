import Foundation

public enum CLIClientError: Error, Equatable {
    case executableNotFound(String)
    case nonzeroExit(Int32, stderr: String)
    case timedOut
    case noOutput
}

/// Locates an executable by name. Checks a list of common install locations
/// before falling back to a PATH lookup via `/usr/bin/which`. Returns nil if
/// nothing is found — callers should surface a clear "install the CLI"
/// error rather than crashing.
public enum CLILocator {
    public static func find(_ name: String) -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "\(home)/.npm-global/bin/\(name)",
            "\(home)/.local/bin/\(name)",
            "/usr/local/opt/node/bin/\(name)",
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        return which(name)
    }

    private static func which(_ name: String) -> String? {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = [name]
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }
}

/// Runs an executable, captures stdout, enforces a timeout. Used by the CLI
/// LLM clients to subprocess `claude`, `codex`, `cursor`, etc.
public struct CLIProcessRunner: Sendable {
    public init() {}

    public func run(
        executable: String,
        arguments: [String],
        stdin: Data? = nil,
        timeout: TimeInterval = 180,
        env: [String: String]? = nil
    ) throws -> String {
        let task = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = Pipe()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.standardOutput = outPipe
        task.standardError = errPipe
        task.standardInput = inPipe
        task.environment = env ?? Self.defaultEnvironment()

        // Drain stdout/stderr on background queues *before* waiting. OS pipe
        // buffers are bounded (~64KB); reading only after exit would deadlock a
        // child that writes more than that (it blocks on write, never exits).
        final class DataBox: @unchecked Sendable { var data = Data() }
        let outBox = DataBox(), errBox = DataBox()
        let drain = DispatchGroup()
        let q = DispatchQueue.global(qos: .userInitiated)

        let sem = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in sem.signal() }

        try task.run()

        drain.enter(); q.async { outBox.data = outPipe.fileHandleForReading.readDataToEndOfFile(); drain.leave() }
        drain.enter(); q.async { errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile(); drain.leave() }

        // Feed stdin on a background queue too, so a large prompt (which may
        // exceed the pipe buffer) can't deadlock against the child reading it.
        if let stdin {
            q.async {
                inPipe.fileHandleForWriting.write(stdin)
                try? inPipe.fileHandleForWriting.close()
            }
        } else {
            try? inPipe.fileHandleForWriting.close()
        }

        if sem.wait(timeout: .now() + timeout) == .timedOut {
            // Escalate: SIGTERM, brief grace, then SIGKILL; reap so we don't
            // leak the process or its pipe file descriptors.
            task.terminate()
            if drain.wait(timeout: .now() + 2) == .timedOut, task.isRunning {
                kill(task.processIdentifier, SIGKILL)
            }
            task.waitUntilExit()
            throw CLIClientError.timedOut
        }

        // Process exited; ensure both readers have hit EOF before using buffers.
        drain.wait()
        let outData = outBox.data
        let errData = errBox.data

        guard task.terminationStatus == 0 else {
            // CLIs like `claude` print auth/quota errors (e.g. a 401) to stdout,
            // not stderr. Fall back to stdout so the failure is diagnosable
            // instead of surfacing an empty `stderr: ""`.
            let err = String(data: errData, encoding: .utf8) ?? ""
            let out = String(data: outData, encoding: .utf8) ?? ""
            let detail = err.isEmpty ? out.trimmingCharacters(in: .whitespacesAndNewlines) : err
            throw CLIClientError.nonzeroExit(task.terminationStatus, stderr: detail)
        }
        guard let s = String(data: outData, encoding: .utf8) else {
            throw CLIClientError.noOutput
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Pass-through environment with PATH expanded so child processes can find
    /// node/python interpreters that wrap the CLI tools.
    public static func defaultEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        let existing = env["PATH"] ?? ""
        let parts = existing.split(separator: ":").map(String.init)
        env["PATH"] = (extra + parts).joined(separator: ":")
        return env
    }
}
