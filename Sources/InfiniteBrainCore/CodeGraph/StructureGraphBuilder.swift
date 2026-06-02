import Foundation
import CoreGraphics

/// Converts a ScanResult into CGData: one node per file, one per symbol,
/// contains edges (file→symbol), imports edges (file→file).
public enum StructureGraphBuilder {

    public static func build(_ scan: ScanResult, repoRoot: URL) -> CGData {
        var nodes:   [CGNode] = []
        var edges:   [CGEdge] = []
        var nodeIds = Set<String>()

        // File nodes.
        for f in scan.files {
            let id   = "file:\(f.path)"
            let abs  = repoRoot.appendingPathComponent(f.path).absoluteString
            let kind: CGNodeKind = f.language == "markdown" ? .docPage : .file
            nodeIds.insert(id)
            nodes.append(CGNode(
                id: id,
                title: (f.path as NSString).lastPathComponent,
                kind: kind,
                position: .zero,
                metadata: ["source_file": f.path, "fileURL": abs,
                           "language": f.language, "loc": String(f.loc)]))
        }

        // Symbol nodes + contains edges.
        for f in scan.files {
            let fileId = "file:\(f.path)"
            let abs    = repoRoot.appendingPathComponent(f.path).absoluteString
            for sym in scan.symbols[f.path] ?? [] {
                let kind: CGNodeKind
                let prefix: String
                switch sym.kind {
                case "class":   kind = .classType; prefix = "class"
                case "heading": kind = .docPage;   prefix = "heading"
                default:        kind = .function;  prefix = "function"
                }
                let id = "\(prefix):\(f.path):\(sym.name)"
                guard !nodeIds.contains(id) else { continue }
                nodeIds.insert(id)
                var symMeta: [String: String] = ["source_file": f.path, "fileURL": abs, "line": "L\(sym.line)"]
                if let decl = sym.declaration { symMeta["declaration"] = decl }
                nodes.append(CGNode(id: id, title: sym.name, kind: kind, position: .zero, metadata: symMeta))
                edges.append(CGEdge(fromId: fileId, toId: id, kind: .contains))
            }
        }

        // Import edges (file → file).
        for (src, targets) in scan.imports {
            let srcId = "file:\(src)"
            guard nodeIds.contains(srcId) else { continue }
            for t in targets {
                let dstId = "file:\(t)"
                guard nodeIds.contains(dstId) else { continue }
                edges.append(CGEdge(fromId: srcId, toId: dstId, kind: .imports))
            }
        }

        return CGData(nodes: nodes, edges: edges)
    }
}
