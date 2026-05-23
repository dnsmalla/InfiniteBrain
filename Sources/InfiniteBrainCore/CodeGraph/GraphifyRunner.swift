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

        do {
            let (exit, _, stderr) = try await launcher.run(executable: bin, arguments: args, environment: nil)
            if exit != 0 {
                let tail = String(data: stderr.suffix(800), encoding: .utf8) ?? ""
                return .failure(.runFailed(exitCode: exit, stderrTail: tail))
            }
            guard FileManager.default.fileExists(atPath: outJSON.path) else {
                return .failure(.parseFailed(message: "graphify produced no output at \(outJSON.path)"))
            }
            return .success(outJSON)
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.runFailed(exitCode: -1, stderrTail: String(describing: error)))
        }
    }
}
