import Foundation

/// Enumerates Swift / TypeScript / JavaScript files via `git ls-files`
/// and extracts imports + symbols by reading each file line-by-line.
/// Pure static helpers (language, importSpecifier, symbol) are separated
/// for testability. Python files are skipped here and handled by
/// PythonASTExtractor.
public final class FileStructureExtractor {
    private let launcher: ProcessLauncher
    private let gitURL: URL?

    public init(launcher: ProcessLauncher,
                gitURL: URL? = FileStructureExtractor.resolve("git")) {
        self.launcher = launcher
        self.gitURL   = gitURL
    }

    public static func resolve(_ name: String) -> URL? {
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let cand = URL(fileURLWithPath: String(dir)).appendingPathComponent(name)
                if FileManager.default.isExecutableFile(atPath: cand.path) { return cand }
            }
        }
        for p in ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"] {
            if FileManager.default.isExecutableFile(atPath: p) { return URL(fileURLWithPath: p) }
        }
        return nil
    }

    // MARK: - Pure helpers (public for tests)

    public static let codeExtensions: Set<String> = ["ts", "tsx", "js", "jsx", "mjs", "cjs", "swift", "md"]

    public static func language(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "ts", "tsx":                return "typescript"
        case "js", "jsx", "mjs", "cjs": return "javascript"
        case "swift":                    return "swift"
        case "md":                       return "markdown"
        default:                         return "other"
        }
    }

    /// Extract a markdown heading (## or ###) as a symbol, or nil.
    public static func markdownHeading(fromLine line: String, lineNumber: Int) -> ScanResult.Symbol? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("## ") || trimmed.hasPrefix("### ") else { return nil }
        let name = trimmed.drop(while: { $0 == "#" || $0 == " " })
            .trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return ScanResult.Symbol(name: name, kind: "heading", line: lineNumber)
    }

    /// Extract the import specifier from a single source line, or nil.
    public static func importSpecifier(fromLine line: String, language: String) -> String? {
        switch language {
        case "typescript", "javascript":
            if let r = firstQuoted(in: line),
               line.contains("import") || line.contains("require") { return r }
            return nil
        case "swift":
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("import ") else { return nil }
            let mod = trimmed.dropFirst("import ".count).trimmingCharacters(in: .whitespaces)
            return mod.split(whereSeparator: { $0 == " " }).first.map(String.init)
        default:
            return nil
        }
    }

    /// Extract a defined symbol from a single line, or nil. Line number set to 0;
    /// caller fills in actual line number.
    public static func symbol(fromLine line: String, language: String) -> ScanResult.Symbol? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        func nameAfter(_ keyword: String) -> String? {
            guard let r = trimmed.range(of: keyword + " ") else { return nil }
            let rest = trimmed[r.upperBound...]
            let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            return name.isEmpty ? nil : String(name)
        }
        switch language {
        case "typescript", "javascript":
            if let n = nameAfter("function") { return .init(name: n, kind: "function", line: 0) }
            if let n = nameAfter("class")    { return .init(name: n, kind: "class",    line: 0) }
            return nil
        case "swift":
            if let n = nameAfter("func")     { return .init(name: n, kind: "function", line: 0) }
            if let n = nameAfter("class")    { return .init(name: n, kind: "class",    line: 0) }
            if let n = nameAfter("struct")   { return .init(name: n, kind: "class",    line: 0) }
            if let n = nameAfter("enum")     { return .init(name: n, kind: "class",    line: 0) }
            if let n = nameAfter("protocol") { return .init(name: n, kind: "class",    line: 0) }
            return nil
        default:
            return nil
        }
    }

    static func firstQuoted(in line: String) -> String? {
        for quote in ["'", "\""] {
            if let start = line.range(of: quote),
               let end   = line.range(of: quote, range: start.upperBound..<line.endIndex) {
                return String(line[start.upperBound..<end.lowerBound])
            }
        }
        return nil
    }

    // MARK: - Orchestration

    /// List tracked files via `git -C <repoRoot> ls-files`, then parse each.
    /// Returns [] if git is unavailable or the folder is not a git repo.
    public func run(repoRoot: URL) async -> [RawFileStructure] {
        guard let git = gitURL else { return fallbackEnumerate(repoRoot: repoRoot) }
        let listing: Data
        do {
            let (exit, out, _) = try await launcher.run(
                executable: git,
                arguments: ["-C", repoRoot.path, "ls-files"],
                environment: nil)
            guard exit == 0 else { return fallbackEnumerate(repoRoot: repoRoot) }
            listing = out
        } catch { return fallbackEnumerate(repoRoot: repoRoot) }

        let paths = (String(data: listing, encoding: .utf8) ?? "")
            .split(separator: "\n").map(String.init)
            .filter { p in
                let ext = (p as NSString).pathExtension.lowercased()
                return Self.codeExtensions.contains(ext)
            }

        return parseFiles(paths: paths, repoRoot: repoRoot)
    }

    /// Fallback when git is unavailable: FileManager recursive enumeration.
    private func fallbackEnumerate(repoRoot: URL) -> [RawFileStructure] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: repoRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let skipDirs: Set<String> = [".git", "node_modules", ".build", "dist", "build",
                                     ".venv", "venv", "__pycache__", ".code-notes",
                                     ".understand-anything", ".mypy_cache"]
        var paths: [String] = []
        for case let url as URL in enumerator {
            if let name = url.pathComponents.last, skipDirs.contains(name) {
                enumerator.skipDescendants(); continue
            }
            let ext = url.pathExtension.lowercased()
            guard Self.codeExtensions.contains(ext) else { continue }
            let rel = url.path.hasPrefix(repoRoot.path + "/")
                ? String(url.path.dropFirst(repoRoot.path.count + 1))
                : url.path
            paths.append(rel)
        }
        return parseFiles(paths: paths.sorted(), repoRoot: repoRoot)
    }

    private func parseFiles(paths: [String], repoRoot: URL) -> [RawFileStructure] {
        paths.compactMap { path -> RawFileStructure? in
            let lang = Self.language(for: path)
            let url  = repoRoot.appendingPathComponent(path)
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            var imports: [RawImport] = []
            var symbols: [ScanResult.Symbol] = []
            var loc = 0
            for (idx, raw) in content.split(separator: "\n",
                                             omittingEmptySubsequences: false).enumerated() {
                let line = String(raw)
                if !line.trimmingCharacters(in: .whitespaces).isEmpty { loc += 1 }
                if lang == "markdown" {
                    if let sym = Self.markdownHeading(fromLine: line, lineNumber: idx + 1) {
                        symbols.append(sym)
                    }
                } else {
                    if let spec = Self.importSpecifier(fromLine: line, language: lang) {
                        imports.append(RawImport(module: spec))
                    }
                    if var sym = Self.symbol(fromLine: line, language: lang) {
                        sym = ScanResult.Symbol(name: sym.name, kind: sym.kind, line: idx + 1)
                        symbols.append(sym)
                    }
                }
            }
            return RawFileStructure(path: path, language: lang, loc: loc,
                                    rawImports: imports, symbols: symbols)
        }
    }
}
