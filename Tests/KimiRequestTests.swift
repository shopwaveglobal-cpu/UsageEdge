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
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let tokenFile = directory.appendingPathComponent("server.token")
  try! Data("test-token\n".utf8).write(to: tokenFile)
  precondition(KimiLocalRequest.readToken(from: tokenFile) == "test-token")
  try! Data("bad token".utf8).write(to: tokenFile)
  precondition(KimiLocalRequest.readToken(from: tokenFile) == nil)
  try! Data(repeating: 65, count: 4097).write(to: tokenFile)
  precondition(KimiLocalRequest.readToken(from: tokenFile) == nil)
  let link = directory.appendingPathComponent("link")
  try! FileManager.default.createSymbolicLink(at: link, withDestinationURL: tokenFile)
  precondition(KimiLocalRequest.readToken(from: link) == nil)
  print("Kimi 로컬 요청 검사 통과")
 }
}
