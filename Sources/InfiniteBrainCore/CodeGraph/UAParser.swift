import Foundation
import CoreGraphics

public enum UAParser {

    private struct RawGraph: Decodable {
        let version: String?
        let nodes: [RawNode]?
        let edges: [RawEdge]?
        let layers: [RawLayer]?
        let tour: [RawTourStep]?
    }
    private struct RawNode: Decodable {
        let id: String
        let type: String?
        let name: String?
        let filePath: String?
        let lineRange: [Int]?
        let summary: String?
        let tags: [String]?
        let complexity: String?
    }
    private struct RawEdge: Decodable {
        let source: String
        let target: String
        let type: String
        let direction: String?
        let weight: Double?
    }
    private struct RawLayer: Decodable {
        let id: String
        let name: String
        let description: String?
        let nodeIds: [String]
    }
    private struct RawTourStep: Decodable {
        let order: Int?
        let title: String?
        let description: String?
        let nodeIds: [String]?
        let languageLesson: String?
    }

    /// Decode understand-anything's `knowledge-graph.json` into `CGData`.
    /// `repoRoot` converts relative `filePath` values to absolute `file://` URLs.
    public static func parse(data: Data, repoRoot: URL) throws -> CGData {
        let raw: RawGraph
        do { raw = try JSONDecoder().decode(RawGraph.self, from: data) }
        catch { throw UAError.parseFailed(message: error.localizedDescription) }

        guard let rawNodes = raw.nodes else {
            throw UAError.parseFailed(message: "knowledge-graph.json has no `nodes` field")
        }
        let rawEdges  = raw.edges  ?? []
        let rawLayers = raw.layers ?? []
        let rawTour   = raw.tour   ?? []

        let nodes: [CGNode] = rawNodes.map { rn in
            let kind = mapNodeType(rn.type)
            var meta: [String: String] = [:]

            if let fp = rn.filePath, !fp.isEmpty {
                let abs = resolveFileURL(filePath: fp, repoRoot: repoRoot)
                meta["fileURL"] = abs.absoluteString
                let rootPath = repoRoot.standardizedFileURL.path
                let absPath  = abs.standardizedFileURL.path
                meta["source_file"] = absPath.hasPrefix(rootPath + "/")
                    ? String(absPath.dropFirst(rootPath.count + 1))
                    : fp
            }
            if let lr = rn.lineRange {
                meta["line"] = lr.count >= 2 ? "L\(lr[0])-L\(lr[1])" : "L\(lr[0])"
            }
            if let s = rn.summary,    !s.isEmpty { meta["summary"]    = s }
            if let c = rn.complexity, !c.isEmpty { meta["complexity"] = c }
            if let t = rn.tags,       !t.isEmpty { meta["tags"]       = t.joined(separator: ", ") }
            if let t = rn.type,       !t.isEmpty { meta["ua_type"]    = t }

            return CGNode(id: rn.id, title: rn.name ?? rn.id,
                          kind: kind, position: .zero, metadata: meta)
        }

        let edges: [CGEdge] = rawEdges.map { re in
            CGEdge(fromId: re.source, toId: re.target, kind: mapEdgeType(re.type))
        }

        let layers: [UALayer] = rawLayers.map { rl in
            UALayer(id: rl.id, name: rl.name, nodeIds: rl.nodeIds)
        }

        let tour: [UATourStep] = rawTour
            .sorted { ($0.order ?? 0) < ($1.order ?? 0) }
            .compactMap { rt in
                guard let nodeId = rt.nodeIds?.first else { return nil }
                return UATourStep(nodeId: nodeId,
                                  title: rt.title ?? "Step \(rt.order ?? 0)",
                                  body:  rt.description ?? rt.languageLesson ?? "")
            }

        return CGData(nodes: nodes, edges: edges, layers: layers, tour: tour)
    }

    public static func mapNodeType(_ raw: String?) -> CGNodeKind {
        switch (raw ?? "").lowercased() {
        case "file":                      return .file
        case "module", "package":         return .module
        case "document", "doc":           return .docPage
        case "function", "func":          return .function
        case "class", "struct":           return .classType
        case "config", "configuration":   return .config
        case "service":                   return .service
        case "table":                     return .table
        case "endpoint", "api":           return .endpoint
        case "pipeline":                  return .pipeline
        case "schema":                    return .schemaNode
        case "resource":                  return .resource
        case "domain":                    return .domain
        case "flow":                      return .flow
        case "step":                      return .step
        case "article":                   return .article
        case "entity":                    return .entity
        case "topic":                     return .topic
        case "claim":                     return .claim
        case "symbol", "method", "interface": return .symbol
        default:                          return .other
        }
    }

    public static func mapEdgeType(_ raw: String) -> CGEdgeKind {
        switch raw.lowercased() {
        case "imports":                           return .imports
        case "exports":                           return .exports
        case "contains":                          return .contains
        case "inherits", "extends", "extends_from": return .inherits
        case "implements":                        return .implements
        case "calls", "invokes":                  return .calls
        case "subscribes", "listens":             return .subscribes
        case "publishes", "emits":                return .publishes
        case "middleware":                        return .middleware
        case "reads_from", "readsfrom", "reads":  return .readsFrom
        case "writes_to", "writesto", "writes":   return .writesTo
        case "transforms":                        return .transforms
        case "validates":                         return .validates
        case "depends_on", "dependson", "uses", "requires": return .dependsOn
        case "tested_by", "testedby", "tests":   return .testedBy
        case "configures":                        return .configures
        case "related_to", "relatedto":           return .relatedTo
        case "similar_to", "similarto":           return .similarTo
        case "deploys":                           return .deploys
        case "serves":                            return .serves
        case "provisions":                        return .provisions
        case "triggers":                          return .triggers
        case "migrates":                          return .migrates
        case "documents":                         return .documents
        case "routes":                            return .routes
        case "defines_schema":                    return .definesSchema
        case "contains_flow":                     return .containsFlow
        case "flow_step":                         return .flowStep
        case "cross_domain":                      return .crossDomain
        case "cites":                             return .cites
        case "contradicts", "opposes":            return .contradicts
        case "builds_on", "buildson", "extends_idea": return .buildsOn
        case "exemplifies", "illustrates":        return .exemplifies
        case "categorized_under", "tagged":       return .categorizedUnder
        case "authored_by", "written_by":         return .authoredBy
        case "defines", "method", "case_of":      return .defines
        case "references":                        return .references
        default:                                  return .relatedTo
        }
    }

    public static func resolveFileURL(filePath: String, repoRoot: URL) -> URL {
        if !filePath.hasPrefix("/") {
            return repoRoot.appendingPathComponent(filePath, isDirectory: false)
        }
        let rootPath = repoRoot.standardizedFileURL.path
        if filePath.hasPrefix(rootPath + "/") || filePath == rootPath {
            return URL(fileURLWithPath: filePath)
        }
        let needle = "/\(repoRoot.lastPathComponent)/"
        if let range = filePath.range(of: needle, options: .backwards) {
            return repoRoot.appendingPathComponent(
                String(filePath[range.upperBound...]), isDirectory: false)
        }
        return URL(fileURLWithPath: filePath)
    }
}
