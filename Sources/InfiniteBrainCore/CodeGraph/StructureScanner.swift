import Foundation

public final class StructureScanner {
    private let fileExtractor:   FileStructureExtractor
    private let pythonExtractor: PythonASTExtractor

    public init(launcher: ProcessLauncher) {
        self.fileExtractor   = FileStructureExtractor(launcher: launcher)
        self.pythonExtractor = PythonASTExtractor(launcher: launcher)
    }

    public func scan(repoRoot: URL) async -> ScanResult {
        let aliases = ImportResolver.loadTsconfigAliases(repoRoot: repoRoot)
        async let fileRaws   = fileExtractor.run(repoRoot: repoRoot)
        async let pythonRaws = pythonExtractor.run(repoRoot: repoRoot)
        let raws = await fileRaws + pythonRaws
        return Self.assemble(raws, aliases: aliases)
    }

    public static func assemble(_ raws: [RawFileStructure],
                                aliases: [String: String] = [:]) -> ScanResult {
        var byPath: [String: RawFileStructure] = [:]
        for r in raws where byPath[r.path] == nil { byPath[r.path] = r }
        let all     = byPath.values.sorted { $0.path < $1.path }
        let fileSet = Set(all.map { $0.path })

        var files:      [ScanResult.FileEntry]              = []
        var imports:    [String: [String]]                  = [:]
        var symbols:    [String: [ScanResult.Symbol]]       = [:]
        var calls:      [String: [ScanResult.CallRef]]      = [:]
        var inherits:   [String: [ScanResult.InheritRef]]   = [:]
        var implements: [String: [ScanResult.ImplementRef]] = [:]

        for r in all {
            files.append(.init(path: r.path, language: r.language, loc: r.loc))
            symbols[r.path]    = r.symbols
            calls[r.path]      = r.calls
            inherits[r.path]   = r.inherits
            implements[r.path] = r.implements

            var resolved: [String] = []
            for imp in r.rawImports {
                if let target = ImportResolver.resolve(imp, fromFile: r.path,
                                                       language: r.language,
                                                       files: fileSet,
                                                       aliases: aliases),
                   target != r.path {
                    resolved.append(target)
                }
            }
            var seen = Set<String>()
            imports[r.path] = resolved.filter { seen.insert($0).inserted }
        }

        return ScanResult(files: files, imports: imports, symbols: symbols,
                          calls: calls, inherits: inherits, implements: implements)
    }
}
