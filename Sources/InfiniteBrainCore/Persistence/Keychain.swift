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

        // Clearing the value: delete the item.
        guard let value, let data = value.data(using: .utf8) else {
            let del = SecItemDelete(base as CFDictionary)
            if del != errSecSuccess && del != errSecItemNotFound { throw KeychainError.osStatus(del) }
            return
        }

        // `…ThisDeviceOnly` keeps the API key off iCloud Keychain and out of
        // backups. Update-in-place when the item exists (instead of delete-then-add,
        // which had a window where an interrupted call left the key gone).
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(base as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            if addStatus != errSecSuccess { throw KeychainError.osStatus(addStatus) }
            return
        }
        throw KeychainError.osStatus(updateStatus)
    }
}
