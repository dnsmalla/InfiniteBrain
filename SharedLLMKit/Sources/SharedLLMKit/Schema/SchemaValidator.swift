import Foundation

public enum SchemaValidationError: Error, Equatable {
    case missing(String)
    case typeMismatch(field: String, expected: String)
}

/// Validates a JSON dictionary against a simple type-tag schema such as the
/// one declared in a SKILL.md `outputs:` block. Recognised tags:
///   string · number · integer · boolean · array · object · enum · any
///
/// `enum` accepts any string — the legal value set is documented in the
/// skill body and re-checked by the orchestrator if it cares to.
public struct SchemaValidator: Sendable {
    public init() {}

    public func validate(_ value: [String: Any], schema: [String: String]) throws {
        for (field, tag) in schema {
            guard let v = value[field] else {
                throw SchemaValidationError.missing(field)
            }
            guard Self.matches(v, tag: tag) else {
                throw SchemaValidationError.typeMismatch(field: field, expected: tag)
            }
        }
    }

    private static func matches(_ v: Any, tag: String) -> Bool {
        switch tag {
        case "any":
            return true
        case "string", "enum":
            return v is String
        case "integer":
            if v is Int { return true }
            if let n = v as? NSNumber, CFNumberIsFloatType(n as CFNumber) == false { return true }
            return false
        case "number":
            return v is Int || v is Double || v is Float || v is NSNumber
        case "boolean":
            return v is Bool
        case "array":
            return v is [Any]
        case "object":
            return v is [String: Any]
        default:
            return true   // unknown tag → permissive (rules can be added later)
        }
    }
}
