import XCTest
@testable import InfiniteBrain

final class AppSettingsTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // Use an isolated UserDefaults suite so tests don't pollute the real plist.
        defaults = UserDefaults(suiteName: "InfiniteBrainTests-\(UUID().uuidString)")!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().description)
        super.tearDown()
    }

    func testVaultPathRoundTrip() {
        let settings = AppSettings(defaults: defaults, keychain: InMemoryKeychain())
        XCTAssertNil(settings.vaultPath)
        let url = URL(fileURLWithPath: "/tmp/my-vault")
        settings.vaultPath = url
        XCTAssertEqual(settings.vaultPath, url)

        // Re-instantiate to prove persistence.
        let reopened = AppSettings(defaults: defaults, keychain: InMemoryKeychain())
        XCTAssertEqual(reopened.vaultPath, url)
    }

    func testAPIKeyRoundTripViaKeychain() throws {
        let kc = InMemoryKeychain()
        let settings = AppSettings(defaults: defaults, keychain: kc)
        XCTAssertNil(try settings.apiKey())
        try settings.setAPIKey("sk-ant-abc123")
        XCTAssertEqual(try settings.apiKey(), "sk-ant-abc123")
        try settings.setAPIKey(nil)
        XCTAssertNil(try settings.apiKey())
    }

    func testAPIKeyConfigurationFlag() throws {
        let settings = AppSettings(defaults: defaults, keychain: InMemoryKeychain())
        XCTAssertFalse(settings.isConfigured)
        settings.vaultPath = URL(fileURLWithPath: "/tmp/v")
        XCTAssertFalse(settings.isConfigured, "configured requires vault AND api key")
        try settings.setAPIKey("sk-ant-abc")
        XCTAssertTrue(settings.isConfigured)
    }
}

/// Keychain double for tests — same protocol, simple dictionary.
final class InMemoryKeychain: KeychainStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()
    func get(_ key: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }; return storage[key]
    }
    func set(_ value: String?, forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        if let value { storage[key] = value } else { storage.removeValue(forKey: key) }
    }
}
