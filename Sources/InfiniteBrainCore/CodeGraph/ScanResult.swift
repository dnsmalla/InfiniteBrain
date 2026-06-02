import Foundation

public struct ScanResult: Sendable {
    public struct FileEntry: Equatable, Sendable {
        public let path: String
        public let language: String
        public let loc: Int
        public init(path: String, language: String, loc: Int) {
            self.path = path; self.language = language; self.loc = loc
        }
    }
    public struct Symbol: Codable, Equatable, Sendable {
        public let name: String
        public let kind: String
        public let line: Int
        /// Trimmed source declaration (everything up to `{` or end of line).
        public let declaration: String?
        public init(name: String, kind: String, line: Int, declaration: String? = nil) {
            self.name = name; self.kind = kind; self.line = line; self.declaration = declaration
        }
    }

    public let files: [FileEntry]
    public let imports: [String: [String]]
    public let symbols: [String: [Symbol]]

    public init(files: [FileEntry], imports: [String: [String]], symbols: [String: [Symbol]]) {
        self.files = files; self.imports = imports; self.symbols = symbols
    }

    public static let empty = ScanResult(files: [], imports: [:], symbols: [:])
}
