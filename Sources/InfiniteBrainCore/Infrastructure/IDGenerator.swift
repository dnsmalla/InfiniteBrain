import Foundation

public protocol IDGenerator: Sendable {
    func next() -> String
}

public protocol DateProvider: Sendable {
    func now() -> Date
}

public struct SystemDateProvider: DateProvider {
    public init() {}
    public func now() -> Date { Date() }
}

/// 26-character ULID-shaped ID generator. Crockford base32, lexicographically
/// sortable by creation time. Good enough for vault note IDs.
public struct ULIDGenerator: IDGenerator {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    private let dateProvider: DateProvider
    public init(dateProvider: DateProvider = SystemDateProvider()) {
        self.dateProvider = dateProvider
    }

    public func next() -> String {
        let ms = UInt64(dateProvider.now().timeIntervalSince1970 * 1000)
        var time = ""
        var t = ms
        for _ in 0..<10 {
            time = String(Self.alphabet[Int(t & 0x1F)]) + time
            t >>= 5
        }
        var rand = ""
        for _ in 0..<16 {
            rand += String(Self.alphabet[Int.random(in: 0..<32)])
        }
        return time + rand
    }
}
