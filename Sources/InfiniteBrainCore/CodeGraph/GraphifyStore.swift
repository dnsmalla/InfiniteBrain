import Foundation
import CryptoKit

public struct RunMetadata: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let nodeCount: Int
    public let edgeCount: Int
    public let graphifyVersion: String
}

public final class GraphifyStore {
    private let baseDirectory: URL
    private let fm = FileManager.default

    public init(baseDirectory: URL? = nil) {
        if let b = baseDirectory {
            self.baseDirectory = b
        } else {
            let appSupport = try! FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)
            self.baseDirectory = appSupport
                .appendingPathComponent("InfiniteBrain", isDirectory: true)
                .appendingPathComponent("CodeGraph", isDirectory: true)
        }
    }

    public static func directoryName(for target: URL) -> String {
        let path = target.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func dir(for target: URL) throws -> URL {
        let d = baseDirectory.appendingPathComponent(Self.directoryName(for: target), isDirectory: true)
        try fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    public func save(graphJSON: Data, for target: URL, nodeCount: Int, edgeCount: Int, graphifyVersion: String) throws {
        let d = try dir(for: target)
        try graphJSON.write(to: d.appendingPathComponent("graph.json"), options: .atomic)
        let meta = RunMetadata(timestamp: Date(), nodeCount: nodeCount, edgeCount: edgeCount, graphifyVersion: graphifyVersion)
        let metaData = try JSONEncoder().encode(meta)
        try metaData.write(to: d.appendingPathComponent("meta.json"), options: .atomic)
    }

    public func loadGraphJSON(for target: URL) -> Data? {
        let url = baseDirectory
            .appendingPathComponent(Self.directoryName(for: target), isDirectory: true)
            .appendingPathComponent("graph.json")
        return try? Data(contentsOf: url)
    }

    public func lastRun(for target: URL) -> RunMetadata? {
        let url = baseDirectory
            .appendingPathComponent(Self.directoryName(for: target), isDirectory: true)
            .appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RunMetadata.self, from: data)
    }
}
