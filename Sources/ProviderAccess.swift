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
 // Uses the existing GitHub CLI session; no token is read by UsageEdge.
 func fetchCopilot() -> String {
  let home = FileManager.default.homeDirectoryForCurrentUser.path
  let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", home + "/.local/bin/gh"]
  guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return "GitHub CLI 설치 필요" }
  func run(_ arguments: [String]) -> Data? {
   let process = Process(); process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
   let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
   var env = ProcessInfo.processInfo.environment; env["GH_PROMPT_DISABLED"] = "1"; env["GH_HOST"] = "github.com"; env["GH_PAGER"] = "cat"; process.environment = env
   do {
    try process.run()
    let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timeout)
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); timeout.cancel()
    return process.terminationStatus == 0 && data.count <= 1_000_000 ? data : nil
   } catch { return nil }
  }
  guard let raw = run(["api", "--hostname", "github.com", "user", "--jq", ".login"]),
        let login = String(data: raw, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
        CopilotBilling.validLogin(login) else { return "GitHub CLI 연결 확인 필요" }
  let endpoint = "users/" + login + "/settings/billing/ai_credit/usage"
  guard let data = run(["api", "--hostname", "github.com", "-H", "Accept: application/vnd.github+json", "-H", "X-GitHub-Api-Version: 2026-03-10", endpoint]),
        let value = CopilotBilling.parse(data) else { return "개인 결제·Plan 읽기 권한 확인" }
  return value
 }
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
 func fetch(_ provider: APIProvider, key: String, completion: @escaping (String, TimeInterval?) -> Void) {
  var request = URLRequest(url: provider.url); request.timeoutInterval = 15
  request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
  let config = URLSessionConfiguration.ephemeral; config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
  let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
  session.dataTask(with: request) { data, response, _ in
   defer { session.finishTasksAndInvalidate() }
   let http = response as? HTTPURLResponse
   let delay = http?.statusCode == 429 ? APIProvider.retryDelay(http?.value(forHTTPHeaderField: "Retry-After")) : nil
   completion(provider.responseStatus(code: http?.statusCode, data: data), delay)
  }.resume()
 }
}
