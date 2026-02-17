import Foundation
import Security

struct KeychainStore {
  let service: String

  func writeString(_ value: String, account: String) throws {
    let data = value.data(using: .utf8) ?? Data()

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]

    // Delete + add ensures the item's access control updates to the currently
    // running app build, avoiding stale ACL prompts after rebuilding.
    _ = SecItemDelete(query as CFDictionary)

    var addQuery = query
    addQuery[kSecValueData as String] = data
    addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    addQuery[kSecAttrLabel as String] = "CopyToAsk OpenAI API Key"
    addQuery[kSecAttrDescription as String] = "OpenAI API key for CopyToAsk"

    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
    }
  }

  func readString(account: String) throws -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    guard let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  func delete(account: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let status = SecItemDelete(query as CFDictionary)
    if status == errSecItemNotFound { return }
    guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
  }
}
