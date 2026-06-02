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
            let id  = "file:\(f.path)"
            let abs = repoRoot.appendingPathComponent(f.path).absoluteString
            nodeIds.insert(id)
            nodes.append(CGNode(
                id: id,
                title: (f.path as NSString).lastPathComponent,
                kind: .file,
                position: .zero,
                metadata: ["source_file": f.path, "fileURL": abs,
                           "language": f.language, "loc": String(f.loc)]))
        }

        // Symbol nodes + contains edges.
        for f in scan.files {
            let fileId = "file:\(f.path)"
            let abs    = repoRoot.appendingPathComponent(f.path).absoluteString
            for sym in scan.symbols[f.path] ?? [] {
                let kind: CGNodeKind = sym.kind == "class" ? .classType : .function
                let prefix = sym.kind == "class" ? "class" : "function"
                let id = "\(prefix):\(f.path):\(sym.name)"
                guard !nodeIds.contains(id) else { continue }
                nodeIds.insert(id)
                nodes.append(CGNode(
                    id: id, title: sym.name, kind: kind, position: .zero,
                    metadata: ["source_file": f.path, "fileURL": abs,
                               "line": "L\(sym.line)"]))
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
