import Foundation

/// Combines FileStructureExtractor (Swift/TS/JS) and PythonASTExtractor,
/// resolves imports, and produces a ScanResult.
public final class StructureScanner {
    private let fileExtractor:   FileStructureExtractor
    private let pythonExtractor: PythonASTExtractor

    public init(launcher: ProcessLauncher) {
        self.fileExtractor   = FileStructureExtractor(launcher: launcher)
        self.pythonExtractor = PythonASTExtractor(launcher: launcher)
    }

    public func scan(repoRoot: URL) async -> ScanResult {
        async let fileRaws   = fileExtractor.run(repoRoot: repoRoot)
        async let pythonRaws = pythonExtractor.run(repoRoot: repoRoot)
        let raws = await fileRaws + pythonRaws
        return Self.assemble(raws)
    }

    public static func assemble(_ raws: [RawFileStructure]) -> ScanResult {
        var byPath: [String: RawFileStructure] = [:]
        for r in raws where byPath[r.path] == nil { byPath[r.path] = r }
        let all     = byPath.values.sorted { $0.path < $1.path }
        let fileSet = Set(all.map { $0.path })

        var files:   [ScanResult.FileEntry]            = []
        var imports: [String: [String]]                = [:]
        var symbols: [String: [ScanResult.Symbol]]     = [:]

        for r in all {
            files.append(.init(path: r.path, language: r.language, loc: r.loc))
            symbols[r.path] = r.symbols
            var resolved: [String] = []
            for imp in r.rawImports {
                if let target = ImportResolver.resolve(imp, fromFile: r.path,
                                                       language: r.language,
                                                       files: fileSet),
                   target != r.path {
                    resolved.append(target)
                }
            }
            var seen = Set<String>()
            imports[r.path] = resolved.filter { seen.insert($0).inserted }
        }
        return ScanResult(files: files, imports: imports, symbols: symbols)
    }
}
