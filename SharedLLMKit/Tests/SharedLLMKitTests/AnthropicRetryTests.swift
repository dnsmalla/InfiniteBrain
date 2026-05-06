import XCTest
@testable import SharedLLMKit

final class AnthropicRetryTests: XCTestCase {
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    func testRetriesOn429ThenSucceeds() async throws {
        let attempts = AttemptCounter()
        StubURLProtocol.responder = { _ in
            let n = attempts.bump()
            if n < 3 {
                return (429, #"{"error":"rate_limit"}"#.data(using: .utf8)!)
            }
            return (200, try JSONSerialization.data(withJSONObject: [
                "content": [["type": "text", "text": "ok"]]
            ]))
        }
        let client = AnthropicClient(apiKey: "k", session: StubURLProtocol.session(),
                                     retryPolicy: .init(maxAttempts: 4, baseDelaySeconds: 0))
        let result = try await client.complete(system: "s", user: "u", responseSchema: nil)
        XCTAssertEqual(result, "ok")
        XCTAssertEqual(attempts.value, 3)  // two 429s + one success
    }

    func testGivesUpAfterMaxAttempts() async throws {
        StubURLProtocol.responder = { _ in (503, Data()) }
        let client = AnthropicClient(apiKey: "k", session: StubURLProtocol.session(),
                                     retryPolicy: .init(maxAttempts: 2, baseDelaySeconds: 0))
        do {
            _ = try await client.complete(system: "s", user: "u", responseSchema: nil)
            XCTFail("expected throw")
        } catch AnthropicClientError.httpStatus(let code, _) {
            XCTAssertEqual(code, 503)
        }
    }

    func testDoesNotRetryOn4xxOtherThan429() async throws {
        let attempts = AttemptCounter()
        StubURLProtocol.responder = { _ in
            _ = attempts.bump()
            return (400, #"{"error":"bad"}"#.data(using: .utf8)!)
        }
        let client = AnthropicClient(apiKey: "k", session: StubURLProtocol.session(),
                                     retryPolicy: .init(maxAttempts: 5, baseDelaySeconds: 0))
        do {
            _ = try await client.complete(system: "s", user: "u", responseSchema: nil)
            XCTFail("expected throw")
        } catch AnthropicClientError.httpStatus(let code, _) {
            XCTAssertEqual(code, 400)
        }
        XCTAssertEqual(attempts.value, 1, "400 must not be retried")
    }
}

final class AttemptCounter: @unchecked Sendable {
    private var n = 0
    private let lock = NSLock()
    func bump() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}
