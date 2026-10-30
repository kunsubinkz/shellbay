import Foundation
import Security

public protocol SecretStore: Sendable {
    func set(_ secret: String, service: String, account: String) throws
    func get(service: String, account: String) -> String?
    func delete(service: String, account: String)
}

public struct KeychainError: Error, LocalizedError { public let status: OSStatus
    public var errorDescription: String? { SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)" } }

public struct KeychainStore: SecretStore {
    public init() {}
    public func set(_ secret: String, service: String, account: String) throws {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(secret.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let st = SecItemAdd(add as CFDictionary, nil)
        if st != errSecSuccess { throw KeychainError(status: st) }
    }
    public func get(service: String, account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    public func delete(service: String, account: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
    }
}

/// In-memory store for tests and previews.
public final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private var d: [String: String] = [:]; private let lock = NSLock()
    public init() {}
    public func set(_ secret: String, service: String, account: String) throws { lock.lock(); d[service + "/" + account] = secret; lock.unlock() }
    public func get(service: String, account: String) -> String? { lock.lock(); defer { lock.unlock() }; return d[service + "/" + account] }
    public func delete(service: String, account: String) { lock.lock(); d[service + "/" + account] = nil; lock.unlock() }
}

public enum SecretService {
    public static func host(_ id: UUID) -> String { "com.shellbay.host.\(id.uuidString)" }
    public static let key = "com.shellbay.key"
    public static let pin = "com.shellbay.pin"
}
