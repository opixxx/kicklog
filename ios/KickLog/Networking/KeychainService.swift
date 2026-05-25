import Foundation
import Security

// 토큰을 Keychain 에 안전하게 저장. Generic kSecClassGenericPassword + service prefix.
enum KeychainService {
    private static let service = "com.opixxx.kicklog"

    static func set(_ value: String, forKey key: String) {
        let data = Data(value.utf8)
        // kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly:
        // - 첫 잠금 해제 후 접근 (백그라운드 HealthKit observer 동작 가능)
        // - ThisDeviceOnly: iCloud 백업/디바이스 이전 시 제외 (JWT 누설 방지)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
