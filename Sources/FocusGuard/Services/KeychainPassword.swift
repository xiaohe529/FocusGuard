import Foundation
import Security

enum KeychainPassword {
    private static let service = "com.focusguard.app"
    private static let account = "lockPassword"

    static func save(_ password: String) throws {
        if password.isEmpty {
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ] as CFDictionary)
            return
        }
        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NSError(domain: "KeychainPassword", code: Int(addStatus),
                          userInfo: [NSLocalizedDescriptionKey: "Failed to save password: \(SecCopyErrorMessageString(addStatus, nil) as String? ?? "unknown")"])
        }
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func verify(_ password: String) -> Bool {
        guard let stored = load() else { return password.isEmpty }
        guard let a = stored.data(using: .utf8), let b = password.data(using: .utf8) else {
            return stored == password
        }
        return a.count == b.count && a.withUnsafeBytes { (pa: UnsafeRawBufferPointer) -> Bool in
            b.withUnsafeBytes { (pb: UnsafeRawBufferPointer) in
                var result: UInt8 = 0
                for i in 0..<a.count {
                    result |= pa[i] ^ pb[i]
                }
                return result == 0
            }
        }
    }

    static func delete() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ] as CFDictionary)
    }
}