import Foundation
import Security

enum TagSecretStore {
    private static let service = "app.metki.reader.tag-secret"

    static func save(uid: String, password: Data, pack: Data) {
        delete(uid: uid)
        let payload = password + pack
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: uid,
            kSecValueData as String: payload,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(uid: String) -> (password: Data, pack: Data)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: uid,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              data.count >= 6 else { return nil }
        return (Data(data.prefix(4)), Data(data.dropFirst(4).prefix(2)))
    }

    static func delete(uid: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: uid
        ]
        SecItemDelete(query as CFDictionary)
    }
}
