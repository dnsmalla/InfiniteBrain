import Foundation

public enum ImportResolver {

    /// Resolve a raw import specifier to a repo-relative file path, or nil
    /// if it points outside the repo (npm package, stdlib, etc.).
    public static func resolve(_ imp: RawImport, fromFile: String,
                               language: String, files: Set<String>,
                               aliases: [String: String] = [:]) -> String? {
        switch language {
        case "python":                   return resolvePython(imp, files: files)
        case "typescript", "javascript": return resolveJS(imp, fromFile: fromFile,
                                                          files: files, aliases: aliases)
        default:                         return nil
        }
    }

    /// Read `paths` from the first tsconfig.json found at common locations
    /// and return a prefix→base-dir mapping.
    /// Example: `"@/*": ["src/*"]` → `["@/": "src/"]`
    public static func loadTsconfigAliases(repoRoot: URL) -> [String: String] {
        let candidates = [
            "tsconfig.json",
            "apps/web/tsconfig.json",
            "apps/web/tsconfig.paths.json",
        ]
        for rel in candidates {
            let url = repoRoot.appendingPathComponent(rel)
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            // paths may live at top level or inside compilerOptions
            let co = json["compilerOptions"] as? [String: Any] ?? json
            guard let paths = co["paths"] as? [String: [String]] else { continue }

            var result: [String: String] = [:]
            for (key, values) in paths {
                guard let val = values.first else { continue }
                let prefix = key.hasSuffix("/*") ? String(key.dropLast(2)) + "/" : key
                let target = val.hasSuffix("/*") ? String(val.dropLast(2)) + "/" : val
                result[prefix] = target
            }
            if !result.isEmpty { return result }
        }
        return [:]
    }

    // MARK: - Private

    private static func resolvePython(_ imp: RawImport, files: Set<String>) -> String? {
        var dotted = [String]()
        if let name = imp.name, !name.isEmpty {
            dotted.append(imp.module.isEmpty ? name : imp.module + "." + name)
        }
        if !imp.module.isEmpty { dotted.append(imp.module) }
        for d in dotted {
            let base = d.split(separator: ".").joined(separator: "/")
            for cand in ["\(base).py", "\(base)/__init__.py"] where files.contains(cand) {
                return cand
            }
        }
        return nil
    }

    private static func resolveJS(_ imp: RawImport, fromFile: String,
                                  files: Set<String>,
                                  aliases: [String: String]) -> String? {
        var spec = imp.module

        // Apply path alias (e.g. "@/lib/api" → "src/lib/api")
        for (prefix, base) in aliases where spec.hasPrefix(prefix) {
            spec = base + spec.dropFirst(prefix.count)
            break
        }

        // After alias rewriting spec may be repo-relative (no leading ./)
        // or still relative (starts with ./ or ../)
        let resolved: String
        if spec.hasPrefix("./") || spec.hasPrefix("../") {
            let dir = (fromFile as NSString).deletingLastPathComponent
            resolved = normalize(joining: dir, spec)
        } else if imp.module != spec {
            // alias was rewritten to a root-relative path
            resolved = spec
        } else {
            // bare package name (react, lodash, etc.) — not in-repo
            return nil
        }

        let exts = ["ts", "tsx", "js", "jsx"]
        for e in exts where files.contains("\(resolved).\(e)") { return "\(resolved).\(e)" }
        for e in exts where files.contains("\(resolved)/index.\(e)") { return "\(resolved)/index.\(e)" }
        if files.contains(resolved) { return resolved }
        return nil
    }

    public static func normalize(joining base: String, _ rel: String) -> String {
        var parts = base.isEmpty ? [] : base.split(separator: "/").map(String.init)
        for comp in rel.split(separator: "/").map(String.init) {
            if comp == "." || comp.isEmpty { continue }
            else if comp == ".." { if !parts.isEmpty { parts.removeLast() } }
            else { parts.append(comp) }
        }
        return parts.joined(separator: "/")
    }
}
