import XCTest
@testable import SharedLLMKit

final class SchemaValidatorTests: XCTestCase {
    private let v = SchemaValidator()

    func testAcceptsValidPayload() throws {
        let schema: [String: String] = [
            "type": "string",
            "confidence": "number",
            "tags": "array",
        ]
        let payload: [String: Any] = [
            "type": "decision",
            "confidence": 0.9,
            "tags": ["a", "b"],
        ]
        XCTAssertNoThrow(try v.validate(payload, schema: schema))
    }

    func testRejectsMissingRequiredField() throws {
        let schema: [String: String] = ["type": "string", "confidence": "number"]
        let payload: [String: Any] = ["type": "decision"]
        XCTAssertThrowsError(try v.validate(payload, schema: schema)) { err in
            guard case SchemaValidationError.missing(let field) = err else {
                return XCTFail("wrong error: \(err)")
            }
            XCTAssertEqual(field, "confidence")
        }
    }

    func testRejectsTypeMismatch() throws {
        let schema: [String: String] = ["confidence": "number"]
        let payload: [String: Any] = ["confidence": "high"]
        XCTAssertThrowsError(try v.validate(payload, schema: schema)) { err in
            guard case SchemaValidationError.typeMismatch(let field, let expected) = err else {
                return XCTFail("wrong error: \(err)")
            }
            XCTAssertEqual(field, "confidence")
            XCTAssertEqual(expected, "number")
        }
    }

    func testEnumAcceptsAnyString() throws {
        // The skill format treats `enum` as "string from a set"; the set itself
        // is documented in the body, not the schema. We accept any string here.
        let schema: [String: String] = ["decision": "enum"]
        let payload: [String: Any] = ["decision": "skip"]
        XCTAssertNoThrow(try v.validate(payload, schema: schema))
    }
}
