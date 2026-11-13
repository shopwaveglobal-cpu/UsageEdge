import Foundation
import CoreFoundation

struct LoginAttempt {
 private var current: UUID?
 mutating func begin() -> UUID { let id = UUID(); current = id; return id }
 mutating func cancel() { current = nil }
 func isCurrent(_ id: UUID) -> Bool { current == id }
 mutating func finish(_ id: UUID) -> Bool {
  guard isCurrent(id) else { return false }
  current = nil; return true
 }
}

enum CodexAuth {
 struct Start { let loginID: String; let url: URL }
 static func parseStart(_ data: Data) -> Start? {
  guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        root["id"] as? Int == 3,
        let result = root["result"] as? [String: Any], result["type"] as? String == "chatgpt",
        let id = result["loginId"] as? String, !id.isEmpty,
        let raw = result["authUrl"] as? String, let url = URL(string: raw),
        url.scheme == "https", let host = url.host?.lowercased(),
        ["chatgpt.com", "auth.openai.com"].contains(host), url.user == nil, url.password == nil,
        url.port == nil || url.port == 443 else { return nil }
  return Start(loginID: id, url: url)
 }
 static func parseCompletion(_ data: Data, loginID: String) -> Bool? {
  guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        root["method"] as? String == "account/login/completed",
        let params = root["params"] as? [String: Any],
        params["loginId"] as? String == loginID,
        let success = params["success"] as? NSNumber, CFGetTypeID(success) == CFBooleanGetTypeID() else { return nil }
  return success.boolValue
 }
}
