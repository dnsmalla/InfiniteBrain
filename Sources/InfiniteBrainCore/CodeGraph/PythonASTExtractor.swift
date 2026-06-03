import Foundation

/// Runs the bundled code_graph_scan.py (tree-sitter, multi-language) or falls
/// back to code_ast_scan.py (Python stdlib ast, Python-only) when tree-sitter
/// is unavailable. Parses the JSON output into [RawFileStructure].
public final class PythonASTExtractor {
    private let launcher:      ProcessLauncher
    private let pythonURL:     URL?
    private let richScriptURL: URL?
    private let fallbackURL:   URL?

    public init(launcher: ProcessLauncher,
                pythonURL:     URL? = PythonASTExtractor.resolvePython(),
                richScriptURL: URL? = PythonASTExtractor.bundledRichScriptURL(),
                fallbackURL:   URL? = PythonASTExtractor.bundledFallbackURL()) {
        self.launcher      = launcher
        self.pythonURL     = pythonURL
        self.richScriptURL = richScriptURL
        self.fallbackURL   = fallbackURL
    }

    public static func resolvePython() -> URL? {
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let cand = URL(fileURLWithPath: String(dir)).appendingPathComponent("python3")
                if FileManager.default.isExecutableFile(atPath: cand.path) { return cand }
            }
        }
        for p in ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"] {
            if FileManager.default.isExecutableFile(atPath: p) { return URL(fileURLWithPath: p) }
        }
        return nil
    }

    public static func bundledRichScriptURL() -> URL? {
        Bundle.module.url(forResource: "code_graph_scan", withExtension: "py")
    }

    public static func bundledFallbackURL() -> URL? {
        Bundle.module.url(forResource: "code_ast_scan", withExtension: "py")
    }

    public func run(repoRoot: URL) async -> [RawFileStructure] {
        guard let python = pythonURL else { return [] }
        if let rich = richScriptURL,
           let results = await runScript(python: python, script: rich,
                                         repoRoot: repoRoot, parser: Self.parseRich) {
            return results
        }
        if let fallback = fallbackURL,
           let results = await runScript(python: python, script: fallback,
                                         repoRoot: repoRoot, parser: Self.parseFallback) {
            return results
        }
        return []
    }

    private func runScript(python: URL, script: URL, repoRoot: URL,
                           parser: (Data) throws -> [RawFileStructure]) async -> [RawFileStructure]? {
        do {
            let (exit, stdout, _) = try await launcher.run(
                executable: python,
                arguments: [script.path, repoRoot.path],
                environment: nil)
            guard exit == 0 else { return nil }
            return try? parser(stdout)
        } catch { return nil }
    }

    // MARK: - Rich format (code_graph_scan.py)

    public static func parseRich(_ data: Data) throws -> [RawFileStructure] {
        struct RawSym: Decodable {
            let name: String; let kind: String; let line: Int
            let declaration: String?; let parent: String?
        }
        struct RawImp: Decodable { let module: String; let line: Int }
        struct RawCall: Decodable { let caller: String; let callee: String; let line: Int }
        struct RawInherit: Decodable { let child: String; let parent: String }
        struct RawImpl: Decodable { let class_name: String; let interface_name: String }
        struct RawFile: Decodable {
            let language: String; let loc: Int
            let imports: [RawImp]; let symbols: [RawSym]
            let calls: [RawCall]; let inherits: [RawInherit]; let implements: [RawImpl]
        }

        let map = try JSONDecoder().decode([String: RawFile].self, from: data)
        return map.map { (path, f) in
            RawFileStructure(
                path: path,
                language: f.language,
                loc: f.loc,
                rawImports: f.imports.map { RawImport(module: $0.module) },
                symbols: f.symbols.map {
                    ScanResult.Symbol(name: $0.name, kind: $0.kind, line: $0.line,
                                      declaration: $0.declaration, parent: $0.parent)
                },
                calls: f.calls.map {
                    ScanResult.CallRef(caller: $0.caller, callee: $0.callee, line: $0.line)
                },
                inherits: f.inherits.map {
                    ScanResult.InheritRef(child: $0.child, parent: $0.parent)
                },
                implements: f.implements.map {
                    ScanResult.ImplementRef(className: $0.class_name, interfaceName: $0.interface_name)
                }
            )
        }.sorted { $0.path < $1.path }
    }

    // MARK: - Fallback format (code_ast_scan.py — Python only)

    public static func parseFallback(_ data: Data) throws -> [RawFileStructure] {
        struct RawSym: Decodable { let name: String; let kind: String; let line: Int }
        struct RawImp: Decodable { let module: String; let name: String? }
        struct RawFile: Decodable { let imports: [RawImp]; let symbols: [RawSym]; let loc: Int }
        let map = try JSONDecoder().decode([String: RawFile].self, from: data)
        return map.map { (path, f) in
            RawFileStructure(
                path: path, language: "python", loc: f.loc,
                rawImports: f.imports.map { RawImport(module: $0.module, name: $0.name) },
                symbols: f.symbols.map {
                    ScanResult.Symbol(name: $0.name, kind: $0.kind, line: $0.line)
                }
            )
        }.sorted { $0.path < $1.path }
    }
}
