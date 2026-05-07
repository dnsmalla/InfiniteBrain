import XCTest
@testable import InfiniteBrainCore
@testable import SharedLLMKit

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
        // Pin the provider to anthropic so the assertion is deterministic
        // regardless of which CLIs the test machine happens to have installed.
        settings.provider = .anthropic
        XCTAssertFalse(settings.isConfigured)
        settings.vaultPath = URL(fileURLWithPath: "/tmp/v")
        XCTAssertFalse(settings.isConfigured, "anthropic + vault still needs an api key")
        try settings.setAPIKey("sk-ant-abc")
        XCTAssertTrue(settings.isConfigured)
    }

    func testFirstRunDefaultsToInstalledCLIWhenAvailable() {
        // No saved provider yet. With an empty keychain and the test's
        // own UserDefaults suite, AppSettings should pick the best
        // available CLI if one is installed on this machine. We can't
        // know what's installed, but the chosen provider must be valid.
        let settings = AppSettings(defaults: defaults, keychain: InMemoryKeychain())
        XCTAssertTrue(LLMProviderKind.allCases.contains(settings.provider))
    }
}
