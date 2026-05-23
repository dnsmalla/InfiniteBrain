import Foundation
import Security

public protocol KeychainStore: Sendable {
    func get(_ key: String) throws -> String?
    func set(_ value: String?, forKey key: String) throws
}

public enum KeychainError: Error {
    case osStatus(OSStatus)
}

/// Generic-password Keychain wrapper, scoped to a service identifier so
/// entries don't collide with other apps.
public final class SystemKeychain: KeychainStore, @unchecked Sendable {
    public let service: String
    public init(service: String = "co.infinitebrain.app") {
        self.service = service
    }

    public func get(_ key: String) throws -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        if status != errSecSuccess { throw KeychainError.osStatus(status) }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ value: String?, forKey key: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let delStatus = SecItemDelete(base as CFDictionary)
        if delStatus != errSecSuccess && delStatus != errSecItemNotFound {
            throw KeychainError.osStatus(delStatus)
        }
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus != errSecSuccess { throw KeychainError.osStatus(addStatus) }
    }
}
