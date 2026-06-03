import Foundation

public struct RawFileStructure: Equatable, Sendable {
    public let path: String
    public let language: String
    public let loc: Int
    public let rawImports: [RawImport]
    public let symbols: [ScanResult.Symbol]
    public let calls: [ScanResult.CallRef]
    public let inherits: [ScanResult.InheritRef]
    public let implements: [ScanResult.ImplementRef]

    public init(path: String, language: String, loc: Int,
                rawImports: [RawImport],
                symbols: [ScanResult.Symbol],
                calls: [ScanResult.CallRef]            = [],
                inherits: [ScanResult.InheritRef]      = [],
                implements: [ScanResult.ImplementRef]  = []) {
        self.path = path; self.language = language; self.loc = loc
        self.rawImports = rawImports; self.symbols = symbols
        self.calls = calls; self.inherits = inherits; self.implements = implements
    }
}

public struct RawImport: Equatable, Sendable {
    public let module: String
    public let name: String?
    public init(module: String, name: String? = nil) {
        self.module = module; self.name = name
    }
}
