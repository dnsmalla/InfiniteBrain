import Foundation
import CoreGraphics

public enum StructureGraphBuilder {

    public static func build(_ scan: ScanResult, repoRoot: URL) -> CGData {
        var nodes:   [CGNode] = []
        var edges:   [CGEdge] = []
        var nodeIds = Set<String>()

        // ── File nodes ───────────────────────────────────────────────────────
        for f in scan.files {
            let id  = "file:\(f.path)"
            let abs = repoRoot.appendingPathComponent(f.path).absoluteString
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

        // ── Symbol nodes + contains edges ────────────────────────────────────
        // Build name→nodeId index for cross-symbol resolution.
        var nameToId: [String: String] = [:]

        for f in scan.files {
            let fileId = "file:\(f.path)"
            let abs    = repoRoot.appendingPathComponent(f.path).absoluteString

            for sym in scan.symbols[f.path] ?? [] {
                let (kind, prefix) = nodeKindAndPrefix(for: sym.kind)
                let id = "\(prefix):\(f.path):\(sym.name)"
                guard !nodeIds.contains(id) else { continue }
                nodeIds.insert(id)
                nameToId[sym.name] = id

                var meta: [String: String] = [
                    "source_file": f.path, "fileURL": abs,
                    "line": "L\(sym.line)", "kind": sym.kind
                ]
                if let decl = sym.declaration { meta["declaration"] = decl }
                nodes.append(CGNode(id: id, title: sym.name, kind: kind,
                                    position: .zero, metadata: meta))

                // Method → parent class; everything else → file.
                if sym.kind == "method", let parentName = sym.parent {
                    let parentId = "class:\(f.path):\(parentName)"
                    let owner = nodeIds.contains(parentId) ? parentId : fileId
                    edges.append(CGEdge(fromId: owner, toId: id, kind: .contains,
                                        confidence: .extracted))
                } else {
                    edges.append(CGEdge(fromId: fileId, toId: id, kind: .contains,
                                        confidence: .extracted))
                }
            }
        }

        // ── Import edges (file → file) ────────────────────────────────────────
        for (src, targets) in scan.imports {
            let srcId = "file:\(src)"
            guard nodeIds.contains(srcId) else { continue }
            for t in targets {
                let dstId = "file:\(t)"
                guard nodeIds.contains(dstId) else { continue }
                edges.append(CGEdge(fromId: srcId, toId: dstId, kind: .imports,
                                    confidence: .extracted))
            }
        }

        // ── Inherits edges (child class → parent class) ───────────────────────
        for (filePath, refs) in scan.inherits {
            for ref in refs {
                let childId = "class:\(filePath):\(ref.child)"
                guard nodeIds.contains(childId) else { continue }
                if let parentId = nameToId[ref.parent], nodeIds.contains(parentId) {
                    edges.append(CGEdge(fromId: childId, toId: parentId, kind: .inherits,
                                        confidence: .extracted))
                }
            }
        }

        // ── Implements edges (class → interface/protocol) ─────────────────────
        for (filePath, refs) in scan.implements {
            for ref in refs {
                let classId = "class:\(filePath):\(ref.className)"
                guard nodeIds.contains(classId) else { continue }
                if let ifaceId = nameToId[ref.interfaceName], nodeIds.contains(ifaceId) {
                    edges.append(CGEdge(fromId: classId, toId: ifaceId, kind: .implements,
                                        confidence: .extracted))
                }
            }
        }

        // ── Calls edges (symbol → symbol, INFERRED) ───────────────────────────
        for (filePath, refs) in scan.calls {
            for ref in refs {
                let callerId = nameToId[ref.caller] ?? "class:\(filePath):\(ref.caller)"
                guard let calleeId = nameToId[ref.callee] else { continue }
                guard nodeIds.contains(callerId), nodeIds.contains(calleeId) else { continue }
                guard callerId != calleeId else { continue }
                edges.append(CGEdge(fromId: callerId, toId: calleeId, kind: .calls,
                                    confidence: .inferred))
            }
        }

        return CGData(nodes: nodes, edges: edges)
    }

    // MARK: - Helpers

    private static func nodeKindAndPrefix(for symKind: String) -> (CGNodeKind, String) {
        switch symKind {
        case "class", "struct", "enum", "protocol", "interface", "extension":
            return (.classType, "class")
        case "method":
            return (.function, "method")
        case "heading":
            return (.docPage, "heading")
        default:
            return (.function, "function")
        }
    }
}
