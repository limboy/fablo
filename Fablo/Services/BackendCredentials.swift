import Foundation
import Security

/// Only connection settings persist on device; library content comes from the service.
actor BackendCredentials {
    static let shared = BackendCredentials()
    private let service = "com.limboy.fablo.backend"
    private let addressKey = "backendAddress"

    func load() throws -> BackendConnection? {
        guard let address = UserDefaults.standard.string(forKey: addressKey) else { return nil }
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
        return try BackendConnection(address: address, token: token)
    }

    func save(_ connection: BackendConnection) throws {
        let address = connection.baseURL.absoluteString
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
        UserDefaults.standard.set(address, forKey: addressKey)
    }
}
