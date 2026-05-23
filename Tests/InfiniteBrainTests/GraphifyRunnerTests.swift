import XCTest
@testable import InfiniteBrainCore

final class GraphifyRunnerTests: XCTestCase {
    final class MockLauncher: ProcessLauncher, @unchecked Sendable {
        var capturedExecutable: URL?
        var capturedArgs: [String] = []
        var exitCode: Int32 = 0
        var stdout: Data = Data()
        var stderr: Data = Data()
        var writeJSONToOutPath: Data? = nil

        func run(executable: URL, arguments: [String], environment: [String: String]?) async throws -> (Int32, Data, Data) {
            capturedExecutable = executable
            capturedArgs = arguments
            if let payload = writeJSONToOutPath,
               let i = arguments.firstIndex(of: "--json-out"),
               i + 1 < arguments.count {
                try payload.write(to: URL(fileURLWithPath: arguments[i + 1]))
            }
            return (exitCode, stdout, stderr)
        }
    }

    func testInvokesGraphifyWithExpectedArgs() async throws {
        let launcher = MockLauncher()
        let payload = #"{"version":"1","nodes":[],"edges":[]}"#.data(using: .utf8)!
        launcher.writeJSONToOutPath = payload
        let runner = GraphifyRunner(launcher: launcher, binaryURL: URL(fileURLWithPath: "/fake/graphify"))

        let jsonURL = try await runner.run(targetFolder: URL(fileURLWithPath: "/repo")).get()

        XCTAssertEqual(launcher.capturedExecutable, URL(fileURLWithPath: "/fake/graphify"))
        XCTAssertEqual(launcher.capturedArgs.first, "extract")
        XCTAssertTrue(launcher.capturedArgs.contains("--json-out"))
        XCTAssertTrue(launcher.capturedArgs.contains("--quiet"))
        XCTAssertEqual(try Data(contentsOf: jsonURL), payload)
    }

    func testBinaryMissingWhenNoneResolvable() async throws {
        let runner = GraphifyRunner(launcher: MockLauncher(), binaryURL: nil)
        let res = await runner.run(targetFolder: URL(fileURLWithPath: "/repo"))
        XCTAssertEqual(res, .failure(.binaryMissing))
    }

    func testRunFailedSurfacesExitCodeAndStderrTail() async throws {
        let launcher = MockLauncher()
        launcher.exitCode = 2
        launcher.stderr = Data("boom\nbang\n".utf8)
        let runner = GraphifyRunner(launcher: launcher, binaryURL: URL(fileURLWithPath: "/fake/graphify"))
        let res = await runner.run(targetFolder: URL(fileURLWithPath: "/repo"))
        guard case .failure(.runFailed(let code, let tail)) = res else {
            return XCTFail("expected runFailed, got \(res)")
        }
        XCTAssertEqual(code, 2)
        XCTAssertTrue(tail.contains("boom"))
    }

    func testInstallHintLiteralIsCorrect() {
        // Guard against a typo: graphify CLI is installed as `graphifyy` (double-y).
        XCTAssertEqual(GraphifyRunner.installHint, "uv tool install graphifyy")
    }
}
