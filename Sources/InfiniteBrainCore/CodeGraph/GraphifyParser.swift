import Foundation
import CoreGraphics

public enum GraphifyParser {
    public static let supportedSchemaVersion = "1"

    private struct RawGraph: Decodable {
        let version: String
        let nodes: [RawNode]
        let edges: [RawEdge]
    }
    private struct RawNode: Decodable {
        let id: String
        let kind: String
        let name: String
        let path: String?
        let line: Int?
        let language: String?
    }
    private struct RawEdge: Decodable {
        let from: String
        let to: String
        let kind: String
    }

    public static func parse(data: Data) throws -> GraphData {
        // Check schema version BEFORE the full decode so a payload missing
        // required fields-but-with-an-unsupported-version surfaces the right
        // error (unsupportedSchema) rather than a generic parseFailed.
        struct VersionProbe: Decodable { let version: String }
        if let probe = try? JSONDecoder().decode(VersionProbe.self, from: data),
           probe.version != supportedSchemaVersion {
            throw GraphifyError.unsupportedSchema(version: probe.version)
        }

        let raw: RawGraph
        do {
            raw = try JSONDecoder().decode(RawGraph.self, from: data)
        } catch {
            throw GraphifyError.parseFailed(message: String(describing: error))
        }
        // If we got here the version probe matched (or the JSON had no `version`
        // field at all, in which case RawGraph's required field would have
        // already thrown parseFailed above). No second guard needed.

        let nodes: [GraphNode] = raw.nodes.map { rn in
            let (type, originalKind) = mapNodeKind(rn.kind)
            var meta: [String: String] = [:]
            if let p = rn.path { meta["fileURL"] = URL(fileURLWithPath: p).absoluteString }
            if let l = rn.line { meta["line"] = String(l) }
            if let lang = rn.language { meta["language"] = lang }
            if let original = originalKind { meta["graphify_kind"] = original }
            return GraphNode(
                id: rn.id, title: rn.name, type: type, summary: "",
                position: .zero,
                metadata: meta.isEmpty ? nil : meta
            )
        }
        let edges: [GraphEdge] = raw.edges.map { re in
            GraphEdge(fromId: re.from, toId: re.to, type: mapEdgeKind(re.kind))
        }
        return GraphData(nodes: nodes, edges: edges)
    }

    private static func mapNodeKind(_ k: String) -> (NodeType, String?) {
        switch k {
        case "file":                       return (.codeFile, nil)
        case "class", "struct",
             "function", "method":         return (.codeSymbol, nil)
        case "module", "package":          return (.codeModule, nil)
        case "markdown_section", "doc":    return (.docPage, nil)
        default:                           return (.custom, k)
        }
    }

    private static func mapEdgeKind(_ k: String) -> EdgeType {
        switch k {
        case "imports":              return .imports
        case "calls":                return .calls
        case "references", "uses":   return .references
        case "defines", "declares":  return .defines
        default:                     return .relatedTo
        }
    }
}
