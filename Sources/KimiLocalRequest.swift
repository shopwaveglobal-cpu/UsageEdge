import Foundation

enum KimiLocalRequest {
 static func readToken(from url: URL) -> String? {
  guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
        attributes[.type] as? FileAttributeType == .typeRegular,
        let size = attributes[.size] as? NSNumber, size.intValue > 0, size.intValue <= 4096,
        let data = try? Data(contentsOf: url), data.count <= 4096,
        let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
        make(port: 58627, token: value) != nil else { return nil }
  return value
 }
 static func make(port: Int, token: String) -> URLRequest? {
  guard (1...65535).contains(port), !token.isEmpty,
        token.utf8.allSatisfy({ (33...126).contains($0) }),
        let url = URL(string: "http://127.0.0.1:\(port)/api/v1/oauth/usage") else { return nil }
  var request = URLRequest(url: url)
  request.timeoutInterval = 15
  request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
  return request
 }
}
