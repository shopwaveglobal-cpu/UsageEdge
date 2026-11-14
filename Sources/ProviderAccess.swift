import Foundation
import Security

final class ProviderAccess: NSObject, URLSessionTaskDelegate {
 private let service = "local.usageedge.providers"
 private func query(_ account: String) -> [String: Any] {
  [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
 }
 func save(_ key: String, for provider: APIProvider) -> Bool { save(key, account: provider.rawValue) }
 func save(_ key: String, account: String) -> Bool {
  let data = Data(key.utf8)
  let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
  if status == errSecSuccess { return true }
  guard status == errSecItemNotFound else { return false }
  var item = query(account); item[kSecValueData as String] = data
  item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
  return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
 }
 func remove(_ provider: APIProvider) -> Bool { remove(account: provider.rawValue) }
 func remove(account: String) -> Bool {
  let status = SecItemDelete(query(account) as CFDictionary)
  return status == errSecSuccess || status == errSecItemNotFound
 }
 func key(_ provider: APIProvider) -> String? { key(account: provider.rawValue) }
 func key(account: String) -> String? {
  var item = query(account); item[kSecReturnData as String] = true; item[kSecMatchLimit as String] = kSecMatchLimitOne
  var result: CFTypeRef?
  guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
  return String(data: data, encoding: .utf8)
 }
 func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
 func fetchKimi(_ request: URLRequest, completion: @escaping (Int?, Data?) -> Void) {
  let config = URLSessionConfiguration.ephemeral
  config.connectionProxyDictionary = [:]
  config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
  let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
  session.dataTask(with: request) { data, response, _ in
   defer { session.finishTasksAndInvalidate() }
   completion((response as? HTTPURLResponse)?.statusCode, data)
  }.resume()
 }
 func fetch(_ provider: APIProvider, key: String, completion: @escaping (String) -> Void) {
  var request = URLRequest(url: provider.url); request.timeoutInterval = 15
  request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
  let config = URLSessionConfiguration.ephemeral; config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
  let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
  session.dataTask(with: request) { data, response, _ in
   defer { session.finishTasksAndInvalidate() }
   completion(provider.responseStatus(code: (response as? HTTPURLResponse)?.statusCode, data: data))
  }.resume()
 }
}
