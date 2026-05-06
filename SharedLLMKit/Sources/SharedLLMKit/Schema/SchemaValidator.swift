import Foundation

/// JSON-schema-style validation. Used to gate skill outputs.
public struct SchemaValidator: Sendable {
    public init() {}

    public func validate(_ value: Any, schema: [String: Any]) throws {
        // implement subset of JSON Schema: type, required, enum, minimum, maximum
        fatalError("not yet implemented")
    }
}
