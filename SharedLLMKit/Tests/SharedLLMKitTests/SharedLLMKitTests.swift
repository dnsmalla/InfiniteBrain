import XCTest
@testable import SharedLLMKit

final class SharedLLMKitTests: XCTestCase {
    func testVersion() {
        XCTAssertFalse(SharedLLMKit.version.isEmpty)
    }
}
