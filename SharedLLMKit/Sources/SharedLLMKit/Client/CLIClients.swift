import Foundation

/// Stitches a system + user prompt into the single text payload that CLI
/// tools accept. Mirrors the convention `ucp-demo` uses.
enum PromptMerge {
    static func merge(system: String, user: String) -> String {
        if system.isEmpty { return user }
        return "System:\n\(system)\n\nUser:\n\(user)"
    }
}

// MARK: - Claude CLI

public struct ClaudeCLIClient: LLMClient {
    public let executablePath: String
    public let timeout: TimeInterval
    private let runner = CLIProcessRunner()

    public init(executablePath: String? = nil, timeout: TimeInterval = 180) throws {
        guard let path = executablePath ?? CLILocator.find("claude") else {
            throw CLIClientError.executableNotFound("claude")
        }
        self.executablePath = path
        self.timeout = timeout
    }

    public func complete(system: String, user: String, responseSchema: [String: Any]?) async throws -> String {
        let prompt = PromptMerge.merge(system: system, user: user)
        return try runner.run(
            executable: executablePath,
            arguments: Self.arguments(prompt: prompt),
            stdin: Data(),
            timeout: timeout
        )
    }

    /// `claude -p <prompt> --output-format text --allow-dangerously-skip-permissions`
    public static func arguments(prompt: String) -> [String] {
        ["-p", prompt, "--output-format", "text", "--allow-dangerously-skip-permissions"]
    }
}

// MARK: - Codex CLI

public struct CodexCLIClient: LLMClient {
    public let executablePath: String
    public let timeout: TimeInterval
    private let runner = CLIProcessRunner()

    public init(executablePath: String? = nil, timeout: TimeInterval = 180) throws {
        guard let path = executablePath ?? CLILocator.find("codex") else {
            throw CLIClientError.executableNotFound("codex")
        }
        self.executablePath = path
        self.timeout = timeout
    }

    public func complete(system: String, user: String, responseSchema: [String: Any]?) async throws -> String {
        let prompt = PromptMerge.merge(system: system, user: user)
        // Codex writes its final reply to a file we have to read back, not to
        // stdout — so we ask for `--output-last-message` and clean up after.
        let outFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("ib-codex-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: outFile) }

        _ = try runner.run(
            executable: executablePath,
            arguments: Self.arguments(outputFile: outFile.path),
            stdin: Data(prompt.utf8),
            timeout: timeout
        )

        let s = try String(contentsOf: outFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { throw CLIClientError.noOutput }
        return s
    }

    /// `codex exec --output-last-message <file> --sandbox read-only --skip-git-repo-check`
    public static func arguments(outputFile: String) -> [String] {
        ["exec", "--output-last-message", outputFile, "--sandbox", "read-only", "--skip-git-repo-check"]
    }
}

// MARK: - Cursor CLI

public struct CursorCLIClient: LLMClient {
    public let executablePath: String
    public let timeout: TimeInterval
    private let runner = CLIProcessRunner()

    public init(executablePath: String? = nil, timeout: TimeInterval = 180) throws {
        let candidates: [String] = {
            let home = NSHomeDirectory()
            return [
                "/opt/homebrew/bin/cursor",
                "/usr/local/bin/cursor",
                "/Applications/Cursor.app/Contents/Resources/app/bin/cursor",
                "\(home)/Applications/Cursor.app/Contents/Resources/app/bin/cursor",
            ]
        }()
        let resolved = executablePath
            ?? candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            ?? CLILocator.find("cursor")
        guard let path = resolved else {
            throw CLIClientError.executableNotFound("cursor")
        }
        self.executablePath = path
        self.timeout = timeout
    }

    public func complete(system: String, user: String, responseSchema: [String: Any]?) async throws -> String {
        let prompt = PromptMerge.merge(system: system, user: user)
        return try runner.run(
            executable: executablePath,
            arguments: Self.arguments(prompt: prompt),
            timeout: timeout
        )
    }

    /// `cursor agent --trust --print <prompt>`
    public static func arguments(prompt: String) -> [String] {
        ["agent", "--trust", "--print", prompt]
    }
}
