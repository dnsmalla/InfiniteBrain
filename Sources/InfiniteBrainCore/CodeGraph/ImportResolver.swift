import Foundation

public enum ImportResolver {

    public static func resolve(_ imp: RawImport, fromFile: String,
                               language: String, files: Set<String>) -> String? {
        switch language {
        case "python":                         return resolvePython(imp, files: files)
        case "typescript", "javascript":       return resolveJS(imp, fromFile: fromFile, files: files)
        default:                               return nil
        }
    }

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
                                  files: Set<String>) -> String? {
        let spec = imp.module
        guard spec.hasPrefix("./") || spec.hasPrefix("../") else { return nil }
        let dir = (fromFile as NSString).deletingLastPathComponent
        let combined = normalize(joining: dir, spec)
        let exts = ["ts", "tsx", "js", "jsx"]
        for e in exts where files.contains("\(combined).\(e)") { return "\(combined).\(e)" }
        for e in exts where files.contains("\(combined)/index.\(e)") { return "\(combined)/index.\(e)" }
        if files.contains(combined) { return combined }
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
