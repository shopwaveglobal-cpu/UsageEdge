import Foundation

enum KimiLocalRequest {
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
