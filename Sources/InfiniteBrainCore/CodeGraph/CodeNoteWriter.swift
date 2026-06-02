import Foundation

/// Generates a markdown note per code file from scan data, writes each
/// note to `repoRoot/.code-notes/notes/<path>.md`, and returns CGNode
/// values so the caller can fold them into the graph immediately.
public enum CodeNoteWriter {

    /// Generate note nodes for all non-markdown files in the scan.
    /// Writes notes to disk as a side-effect (best-effort; failures don't block the graph).
    public static func generateNoteNodes(scan: ScanResult, repoRoot: URL) -> [CGNode] {
        let notesRoot = repoRoot.appendingPathComponent(".code-notes/notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: notesRoot, withIntermediateDirectories: true)

        return scan.files
            .filter { $0.language != "markdown" && $0.language != "other" }
            .compactMap { file -> CGNode? in
                let content  = noteMarkdown(path: file.path, scan: scan)
                let noteURL  = notesRoot.appendingPathComponent(file.path + ".md")
                try? FileManager.default.createDirectory(
                    at: noteURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try? content.write(to: noteURL, atomically: true, encoding: .utf8)

                let noteRelPath = ".code-notes/notes/\(file.path).md"
                return CGNode(
                    id: "note:\(file.path)",
                    title: (file.path as NSString).lastPathComponent + ".md",
                    kind: .docPage,
                    position: .zero,
                    metadata: [
                        "source_file":      noteRelPath,
                        "fileURL":          noteURL.absoluteString,
                        "language":         "markdown",
                        "source_code_file": file.path,
                        "note_content":     content
                    ]
                )
            }
    }

    /// Build the markdown body for a single code file's auto-generated note.
    public static func noteMarkdown(path: String, scan: ScanResult) -> String {
        let entry   = scan.files.first { $0.path == path }
        let lang    = entry?.language ?? "unknown"
        let loc     = entry?.loc ?? 0
        let symbols = scan.symbols[path] ?? []
        let imports = scan.imports[path] ?? []

        var out: [String] = []
        out.append("# \((path as NSString).lastPathComponent)")
        out.append("")
        out.append("> `\(path)`  ·  \(lang)  ·  \(loc) lines")
        out.append("")

        if !imports.isEmpty {
            out.append("## Imports")
            for imp in imports {
                out.append("- `\((imp as NSString).lastPathComponent)`")
            }
            out.append("")
        }

        let types = symbols.filter { $0.kind == "class" }
        if !types.isEmpty {
            out.append("## Types")
            for t in types { out.append("- `\(t.name)` · L\(t.line)") }
            out.append("")
        }

        let funcs = symbols.filter { $0.kind == "function" }
        if !funcs.isEmpty {
            out.append("## Functions")
            for f in funcs { out.append("- `\(f.name)` · L\(f.line)") }
            out.append("")
        }

        return out.joined(separator: "\n")
    }
}
