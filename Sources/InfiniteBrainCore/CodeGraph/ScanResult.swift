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
        public let declaration: String?
        /// Containing class name when kind == "method".
        public let parent: String?
        public init(name: String, kind: String, line: Int,
                    declaration: String? = nil, parent: String? = nil) {
            self.name = name; self.kind = kind; self.line = line
            self.declaration = declaration; self.parent = parent
        }
    }

    /// A function/method calling another within the same file.
    public struct CallRef: Equatable, Sendable {
        public let caller: String
        public let callee: String
        public let line: Int
        public init(caller: String, callee: String, line: Int) {
            self.caller = caller; self.callee = callee; self.line = line
        }
    }

    /// A class that inherits from another class/struct.
    public struct InheritRef: Equatable, Sendable {
        public let child: String
        public let parent: String
        public init(child: String, parent: String) {
            self.child = child; self.parent = parent
        }
    }

    /// A class/struct that implements an interface/protocol.
    public struct ImplementRef: Equatable, Sendable {
        public let className: String
        public let interfaceName: String
        public init(className: String, interfaceName: String) {
            self.className = className; self.interfaceName = interfaceName
        }
    }

    public let files:      [FileEntry]
    public let imports:    [String: [String]]
    public let symbols:    [String: [Symbol]]
    public let calls:      [String: [CallRef]]
    public let inherits:   [String: [InheritRef]]
    public let implements: [String: [ImplementRef]]

    public init(files: [FileEntry],
                imports:    [String: [String]],
                symbols:    [String: [Symbol]],
                calls:      [String: [CallRef]]       = [:],
                inherits:   [String: [InheritRef]]    = [:],
                implements: [String: [ImplementRef]]  = [:]) {
        self.files      = files
        self.imports    = imports
        self.symbols    = symbols
        self.calls      = calls
        self.inherits   = inherits
        self.implements = implements
    }

    public static let empty = ScanResult(files: [], imports: [:], symbols: [:])
}
