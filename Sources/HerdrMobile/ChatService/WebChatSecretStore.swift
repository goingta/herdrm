import Foundation
import Security
import CryptoKit

/// Chat auth is independent of SSH auth and never shared with browser cookie storage.
/// The native profile, normalized service address, selected web machine and binding generation
/// form its Keychain account. Address/machine changes cannot inherit a different binding's token.
enum WebChatSecretStore {
    private static let service = "dev.bybee.herdrm.ios.web-chat"

    static func credential(for configuration: WebChatConfiguration, nativeDeviceID: UUID) -> WebChatCredential? {
        guard var query = try? baseQuery(configuration, nativeDeviceID) else { return nil }
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(WebChatCredential.self, from: data)
    }

    static func setCredential(_ credential: WebChatCredential, for configuration: WebChatConfiguration, nativeDeviceID: UUID) throws {
        let data = try JSONEncoder().encode(credential)
        var query = try baseQuery(configuration, nativeDeviceID)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw MobileDeviceError.keychain(status) }
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(query as CFDictionary, nil)
        guard added == errSecSuccess else { throw MobileDeviceError.keychain(added) }
    }

    static func removeCredential(for configuration: WebChatConfiguration, nativeDeviceID: UUID) throws {
        let status = SecItemDelete(try baseQuery(configuration, nativeDeviceID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw MobileDeviceError.keychain(status) }
    }

    private static func baseQuery(_ configuration: WebChatConfiguration, _ nativeDeviceID: UUID) throws -> [String: Any] {
        let validated = try configuration.validated()
        let address = validated.serviceURL.absoluteString + "|" + validated.machineID
        let digest = SHA256.hash(data: Data(address.utf8)).map { String(format: "%02x", $0) }.joined()
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "\(nativeDeviceID.uuidString)|\(validated.credentialID.uuidString)|\(digest)"]
    }
}
