import Foundation
import CoreGraphics
import InfiniteBrainCore

enum UAHelpers {

    struct CodeArtifact: Identifiable {
        let fileNode: CGNode
        let symbols: [CodeSymbol]
        var id: String { fileNode.id }
    }

    struct CodeSymbol: Identifiable {
        let node: CGNode
        var id: String { node.id }
    }

    /// Group nodes by their `metadata["source_file"]` for the Files & Symbols panel.
    static func collectCodeArtifacts(_ g: CGData) -> [CodeArtifact] {
        var bySource: [String: [CodeSymbol]] = [:]
        var fileHeaderByPath: [String: CGNode] = [:]

        for node in g.nodes {
            guard let source = node.metadata["source_file"], !source.isEmpty else { continue }
            if isPanelNoise(node) { continue }
            if node.kind == .file || node.kind == .docPage {
                fileHeaderByPath[source] = node
            } else if !isHeadingChunk(node) {
                bySource[source, default: []].append(CodeSymbol(node: node))
            }
        }

        let allPaths = Set(bySource.keys).union(fileHeaderByPath.keys)
        let basenameCounts = Dictionary(
            grouping: allPaths,
            by: { ($0 as NSString).lastPathComponent }
        ).mapValues(\.count)

        return allPaths.sorted().compactMap { path -> CodeArtifact? in
            let raw = bySource[path] ?? []
            var seen = Set<String>()
            let syms = raw.sorted { $0.node.title < $1.node.title }.filter { sym in
                let key = "\(sym.node.title)|\(sym.node.metadata["line"] ?? "")"
                return seen.insert(key).inserted
            }
            // Always show .md files even with no headings; skip code files with no symbols.
            let isDoc = fileHeaderByPath[path]?.kind == .docPage
            guard !syms.isEmpty || isDoc else { return nil }

            let basename = (path as NSString).lastPathComponent
            let title    = (basenameCounts[basename] ?? 0) > 1 ? path : basename
            let header: CGNode = fileHeaderByPath[path].map { node in
                CGNode(id: node.id, title: title, kind: node.kind,
                       position: node.position, metadata: node.metadata)
            } ?? CGNode(id: "file:" + path, title: title, kind: .file,
                        position: .zero, metadata: ["source_file": path])
            return CodeArtifact(fileNode: header, symbols: syms)
        }
    }

    static func isPanelNoise(_ node: CGNode) -> Bool {
        let t = node.title
        if t.hasPrefix("code:") { return true }
        if t.hasPrefix(".") && t.hasSuffix("()") {
            return !t.dropFirst().dropLast(2).contains(".")
        }
        return false
    }

    static func isHeadingChunk(_ node: CGNode) -> Bool {
        guard node.kind == .docPage || node.kind == .memoryChunk else { return false }
        guard let line = node.metadata["line"] else { return false }
        return line != "L1"
    }

    /// Canvas size that scales with node count so concentric rings stay readable.
    static func layoutSize(for nodeCount: Int) -> CGSize {
        let base:  CGFloat = 1200
        let extra: CGFloat = CGFloat(max(0, nodeCount - 100)) * 4
        let side = min(base + extra, 8000)
        return CGSize(width: side, height: side * 0.7)
    }

    /// Longest common leading path prefix across all inputs.
    static func commonAncestor(_ paths: [String]) -> String {
        guard !paths.isEmpty else { return "" }
        let split = paths.map { $0.split(separator: "/").map(String.init) }
        guard let first = split.first else { return "" }
        var common: [String] = []
        for (idx, comp) in first.enumerated() {
            if split.allSatisfy({ idx < $0.count && $0[idx] == comp }) {
                common.append(comp)
            } else { break }
        }
        return "/" + common.joined(separator: "/")
    }
}
