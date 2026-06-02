import Foundation
import CryptoKit

public struct UARunMetadata: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let nodeCount: Int
    public let edgeCount: Int
    public let toolVersion: String
}

public final class UAStore {
    private let baseDirectory: URL
    private let fm = FileManager.default

    public init(baseDirectory: URL? = nil) {
        if let b = baseDirectory {
            self.baseDirectory = b
        } else {
            let appSupport = (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true))
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.baseDirectory = appSupport
                .appendingPathComponent("InfiniteBrain", isDirectory: true)
                .appendingPathComponent("CodeGraph",     isDirectory: true)
        }
    }

    public static func directoryName(for target: URL) -> String {
        let path = target.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func dir(for target: URL) throws -> URL {
        let d = baseDirectory.appendingPathComponent(
            Self.directoryName(for: target), isDirectory: true)
        try fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    public func save(graphJSON: Data, for target: URL,
                     nodeCount: Int, edgeCount: Int, toolVersion: String) throws {
        let d = try dir(for: target)
        try graphJSON.write(to: d.appendingPathComponent("knowledge-graph.json"), options: .atomic)
        let meta = UARunMetadata(timestamp: Date(), nodeCount: nodeCount,
                                 edgeCount: edgeCount, toolVersion: toolVersion)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(meta).write(to: d.appendingPathComponent("meta.json"), options: .atomic)
    }

    public func loadGraphJSON(for target: URL) -> Data? {
        let url = baseDirectory
            .appendingPathComponent(Self.directoryName(for: target), isDirectory: true)
            .appendingPathComponent("knowledge-graph.json")
        return try? Data(contentsOf: url)
    }

    public func invalidate(for target: URL) {
        let dir = baseDirectory
            .appendingPathComponent(Self.directoryName(for: target), isDirectory: true)
        try? fm.removeItem(at: dir)
    }

    public func lastRun(for target: URL) -> UARunMetadata? {
        let url = baseDirectory
            .appendingPathComponent(Self.directoryName(for: target), isDirectory: true)
            .appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(UARunMetadata.self, from: data)
    }
}
