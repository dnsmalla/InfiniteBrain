import Foundation

public struct RawFileStructure: Equatable, Sendable {
    public let path: String
    public let language: String
    public let loc: Int
    public let rawImports: [RawImport]
    public let symbols: [ScanResult.Symbol]

    public init(path: String, language: String, loc: Int,
                rawImports: [RawImport], symbols: [ScanResult.Symbol]) {
        self.path = path; self.language = language; self.loc = loc
        self.rawImports = rawImports; self.symbols = symbols
    }
}

public struct RawImport: Equatable, Sendable {
    public let module: String
    public let name: String?
    public init(module: String, name: String? = nil) {
        self.module = module; self.name = name
    }
}
