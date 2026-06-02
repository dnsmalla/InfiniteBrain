import Foundation

public final class UARunner {
    public static let installHint = "npm install -g understand-anything"

    private static let fallbackPaths: [String] = [
        "/opt/homebrew/bin/understand-anything",
        "/usr/local/bin/understand-anything",
        NSString(string: "~/.local/bin/understand-anything").expandingTildeInPath
    ]

    private let launcher: ProcessLauncher
    private let binaryURL: URL?

    public init(launcher: ProcessLauncher = SystemProcessLauncher(),
                binaryURL: URL? = UARunner.resolveBinary()) {
        self.launcher  = launcher
        self.binaryURL = binaryURL
    }

    public static func resolveBinary() -> URL? {
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(dir))
                    .appendingPathComponent("understand-anything")
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        for p in fallbackPaths where FileManager.default.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }

    /// Runs `understand-anything extract <folder> --json-out <path>` and returns
    /// a stable URL to the generated `knowledge-graph.json`.
    public func run(targetFolder: URL) async -> Result<URL, UAError> {
        guard let bin = binaryURL else { return .failure(.binaryMissing) }

        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ua-run-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        } catch {
            return .failure(.runFailed(exitCode: -1,
                                       stderrTail: "failed to create temp dir: \(error)"))
        }

        let outJSON = tmpDir.appendingPathComponent("knowledge-graph.json")
        let args    = ["extract", targetFolder.path, "--json-out", outJSON.path]

        defer { try? FileManager.default.removeItem(at: tmpDir) }

        do {
            let (exit, _, stderr) = try await launcher.run(
                executable: bin, arguments: args, environment: nil)
            if exit != 0 {
                return .failure(.runFailed(exitCode: exit,
                                           stderrTail: Self.safeTail(stderr, maxBytes: 800)))
            }
            guard FileManager.default.fileExists(atPath: outJSON.path) else {
                return .failure(.noOutput)
            }
            let stable = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ua-\(UUID().uuidString).json")
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

    /// Return the last `maxBytes` of `data` decoded as UTF-8, stepping forward
    /// past continuation bytes to land on a valid codepoint boundary.
    public static func safeTail(_ data: Data, maxBytes: Int) -> String {
        guard data.count > maxBytes else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        var start = data.count - maxBytes
        let limit = min(start + 4, data.count)
        while start < limit, (data[start] & 0xC0) == 0x80 { start += 1 }
        return String(data: data.subdata(in: start..<data.count), encoding: .utf8) ?? ""
    }
}
