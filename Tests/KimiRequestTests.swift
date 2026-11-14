import Foundation
@main struct KimiRequestTests {
 static func main() {
  let request = KimiLocalRequest.make(port: 58627, token: "test-token")!
  precondition(request.url?.absoluteString == "http://127.0.0.1:58627/api/v1/oauth/usage")
  precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
  precondition(KimiLocalRequest.make(port: 0, token: "test") == nil)
  precondition(KimiLocalRequest.make(port: 65536, token: "test") == nil)
  precondition(KimiLocalRequest.make(port: 58627, token: "bad\ntoken") == nil)
  precondition(KimiLocalRequest.make(port: 58627, token: "") == nil)
  print("Kimi 로컬 요청 검사 통과")
 }
}
