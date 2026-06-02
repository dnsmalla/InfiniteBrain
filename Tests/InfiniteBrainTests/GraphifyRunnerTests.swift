import XCTest
@testable import InfiniteBrainCore

final class UARunnerTests: XCTestCase {

    final class MockLauncher: ProcessLauncher, @unchecked Sendable {
        var capturedExecutable: URL?
        var capturedArgs: [String] = []
        var exitCode: Int32 = 0
        var stdout: Data = Data()
        var stderr: Data = Data()
        var writeJSONToOutPath: Data? = nil

        func run(executable: URL, arguments: [String],
                 environment: [String: String]?) async throws -> (Int32, Data, Data) {
            capturedExecutable = executable
            capturedArgs = arguments
            if let payload = writeJSONToOutPath,
               let i = arguments.firstIndex(of: "--json-out"),
               i + 1 < arguments.count {
                let outURL = URL(fileURLWithPath: arguments[i + 1])
                try FileManager.default.createDirectory(
                    at: outURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try payload.write(to: outURL)
            }
            return (exitCode, stdout, stderr)
        }
    }

    func testBinaryMissingWhenNoneResolvable() async {
        let runner = UARunner(launcher: MockLauncher(), binaryURL: nil)
        let res = await runner.run(targetFolder: URL(fileURLWithPath: "/repo"))
        XCTAssertEqual(res, .failure(.binaryMissing))
    }

    func testInvokesUnderstandAnythingWithExpectedArgs() async throws {
        let launcher = MockLauncher()
        let payload  = #"{"version":"1.0.0","nodes":[],"edges":[]}"#.data(using: .utf8)!
        launcher.writeJSONToOutPath = payload
        let runner = UARunner(launcher: launcher,
                              binaryURL: URL(fileURLWithPath: "/fake/understand-anything"))

        let jsonURL = try await runner.run(targetFolder: URL(fileURLWithPath: "/repo")).get()
        defer { try? FileManager.default.removeItem(at: jsonURL) }

        XCTAssertEqual(launcher.capturedExecutable,
                       URL(fileURLWithPath: "/fake/understand-anything"))
        XCTAssertEqual(launcher.capturedArgs.first, "extract")
        XCTAssertTrue(launcher.capturedArgs.contains("/repo"))
        XCTAssertTrue(launcher.capturedArgs.contains("--json-out"))
        XCTAssertEqual(try Data(contentsOf: jsonURL), payload)
    }

    func testRunFailedSurfacesExitCodeAndStderr() async {
        let launcher = MockLauncher()
        launcher.exitCode = 1
        launcher.stderr   = Data("something went wrong\n".utf8)
        let runner = UARunner(launcher: launcher,
                              binaryURL: URL(fileURLWithPath: "/fake/understand-anything"))
        let res = await runner.run(targetFolder: URL(fileURLWithPath: "/repo"))
        guard case .failure(.runFailed(let code, let tail)) = res else {
            return XCTFail("expected .runFailed, got \(res)")
        }
        XCTAssertEqual(code, 1)
        XCTAssertTrue(tail.contains("wrong"))
    }

    func testExitZeroButNoOutputReportsNoOutput() async {
        let launcher = MockLauncher()
        launcher.exitCode           = 0
        launcher.writeJSONToOutPath = nil
        let runner = UARunner(launcher: launcher,
                              binaryURL: URL(fileURLWithPath: "/fake/understand-anything"))
        let res = await runner.run(targetFolder: URL(fileURLWithPath: "/repo"))
        XCTAssertEqual(res, .failure(.noOutput))
    }

    func testSafeTailHandlesMidCodepointTruncation() {
        let s    = String(repeating: "héllo ", count: 200)
        let data = Data(s.utf8)
        let tail = UARunner.safeTail(data, maxBytes: 50)
        XCTAssertFalse(tail.isEmpty)
        XCTAssertNotNil(tail.data(using: .utf8))
    }

    func testSafeTailUnderLimitReturnsFullString() {
        XCTAssertEqual(UARunner.safeTail(Data("short".utf8), maxBytes: 800), "short")
    }
}
