import Foundation
import Security

/// Persists the connection settings; server content has a separate disposable cache.
/// iOS keeps the token in Keychain. The Mac app keeps it in its sandboxed preferences instead:
/// the Mac keychain asks for the login password whenever the app's signature changes.
actor BackendCredentials {
    static let shared = BackendCredentials()
    private let service = "com.limboy.fablo.backend"
    private let addressKey = "backendAddress"
    private let tokenKey = "backendToken"

    func load() throws -> BackendConnection? {
        guard let address = UserDefaults.standard.string(forKey: addressKey) else { return nil }
        #if os(macOS)
        guard let token = UserDefaults.standard.string(forKey: tokenKey) else { return nil }
        #else
        var item: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: address,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let token = String(data: data, encoding: .utf8)
        else { throw BackendError.message("无法读取已保存的访问令牌") }
        #endif
        return try BackendConnection(address: address, token: token)
    }

    func save(_ connection: BackendConnection) throws {
        let address = connection.baseURL.absoluteString
        #if os(macOS)
        UserDefaults.standard.set(connection.token, forKey: tokenKey)
        #else
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: address] as [CFString: Any]
        let data = Data(connection.token.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData] = data
            attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw BackendError.message("无法保存访问令牌") }
        #endif
        UserDefaults.standard.set(address, forKey: addressKey)
    }
}
