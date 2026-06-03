import XCTest
@testable import SharedLLMKit

/// Verifies the CLI argument shapes match what `ucp-demo` uses, so a working
/// `claude` / `codex` / `cursor` install on the user's machine just works.
final class CLIClientArgumentTests: XCTestCase {
    func testClaudeArgumentsHaveExpectedFlagsInOrder() {
        // Prompt is fed on stdin (not argv) so vault content stays out of `ps`.
        let args = ClaudeCLIClient.arguments()
        XCTAssertEqual(args, ["-p", "--output-format", "text", "--permission-mode", "acceptEdits"])
    }

    func testCodexArgumentsCarryOutputFileAndReadOnlySandbox() {
        let args = CodexCLIClient.arguments(outputFile: "/tmp/x.txt")
        XCTAssertEqual(args, ["exec", "--output-last-message", "/tmp/x.txt", "--sandbox", "read-only", "--skip-git-repo-check"])
    }

    func testCursorArgumentsUseAgentMode() {
        let args = CursorCLIClient.arguments(prompt: "hi")
        XCTAssertEqual(args, ["agent", "--trust", "--print", "hi"])
    }

    func testProviderKindDisplayNamesAndCases() {
        XCTAssertEqual(LLMProviderKind.allCases.count, 4)
        XCTAssertEqual(LLMProviderKind(rawValue: "anthropic"), .anthropic)
        XCTAssertEqual(LLMProviderKind(rawValue: "claude-cli"), .claudeCLI)
        XCTAssertEqual(LLMProviderKind(rawValue: "codex-cli"), .codexCLI)
        XCTAssertEqual(LLMProviderKind(rawValue: "cursor-cli"), .cursorCLI)
        XCTAssertFalse(LLMProviderKind.anthropic.displayName.isEmpty)
    }

    func testPromptMergeIncludesSystemAndUser() {
        let merged = PromptMerge.merge(system: "be brief", user: "hello")
        XCTAssertTrue(merged.contains("be brief"))
        XCTAssertTrue(merged.contains("hello"))
    }
}
