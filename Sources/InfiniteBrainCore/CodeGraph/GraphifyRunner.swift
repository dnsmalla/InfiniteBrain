import Foundation

public final class GraphifyRunner {
    public static let installHint = "uv tool install graphifyy"
    private static let fallbackPaths = [
        "/opt/homebrew/bin/graphify",
        "/usr/local/bin/graphify",
        NSString(string: "~/.local/bin/graphify").expandingTildeInPath
    ]

    private let launcher: ProcessLauncher
    private let binaryURL: URL?

    public init(launcher: ProcessLauncher = SystemProcessLauncher(),
                binaryURL: URL? = GraphifyRunner.resolveBinary()) {
        self.launcher = launcher
        self.binaryURL = binaryURL
    }

    public static func resolveBinary() -> URL? {
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent("graphify")
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        for p in fallbackPaths {
            if FileManager.default.isExecutableFile(atPath: p) {
                return URL(fileURLWithPath: p)
            }
        }
        return nil
    }

    /// Runs `graphify extract <folder>` and returns the URL to the generated `graph.json`.
    /// The returned URL points to a file inside a per-run temp directory; callers should
    /// read or copy the file before another run overwrites the directory pool.
    public func run(targetFolder: URL) async -> Result<URL, GraphifyError> {
        guard let bin = binaryURL else { return .failure(.binaryMissing) }
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("graphify-run-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        } catch {
            return .failure(.runFailed(exitCode: -1, stderrTail: "failed to create temp dir: \(error)"))
        }
        let outJSON = tmpDir.appendingPathComponent("graph.json")
        let args = ["extract", targetFolder.path, "--json-out", outJSON.path, "--quiet"]

        defer {
            // Best-effort cleanup. We hand the URL back to the caller, so they must
            // copy/read it BEFORE this returns — which they do, synchronously, in
            // CodeGraphView. If we ever change that contract, move cleanup to a
            // disposable returned to the caller.
            try? FileManager.default.removeItem(at: tmpDir)
        }

        do {
            let (exit, _, stderr) = try await launcher.run(executable: bin, arguments: args, environment: nil)
            if exit != 0 {
                return .failure(.runFailed(exitCode: exit, stderrTail: Self.safeTail(stderr, maxBytes: 800)))
            }
            guard FileManager.default.fileExists(atPath: outJSON.path) else {
                return .failure(.noOutput)
            }
            // Copy out of the doomed tmpDir into a stable per-call file the caller owns.
            let stable = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("graphify-\(UUID().uuidString).json")
            do {
                try FileManager.default.copyItem(at: outJSON, to: stable)
                return .success(stable)
            } catch {
                return .failure(.parseFailed(message: "failed to stage output: \(error)"))
            }
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.runFailed(exitCode: -1, stderrTail: String(describing: error)))
        }
    }

    /// Take the last `maxBytes` of stderr and decode as UTF-8, stepping forward
    /// until we land on a codepoint boundary so we don't return "" for
    /// otherwise-readable output that was truncated mid-character.
    static func safeTail(_ data: Data, maxBytes: Int) -> String {
        guard data.count > maxBytes else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        var start = data.count - maxBytes
        // UTF-8 continuation bytes have top bits 10xxxxxx (0x80-0xBF). Skip them
        // to find a valid leading byte. Bound the scan so a pathological input
        // can't loop.
        let limit = min(start + 4, data.count)
        while start < limit, (data[start] & 0xC0) == 0x80 { start += 1 }
        return String(data: data.subdata(in: start..<data.count), encoding: .utf8) ?? ""
    }
}
