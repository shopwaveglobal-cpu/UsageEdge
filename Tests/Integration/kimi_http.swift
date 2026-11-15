import Foundation
@main struct Test {
 static func main() {
  let access = ProviderAccess()
  let port = Int(CommandLine.arguments[1])!
  func check(_ token: String, _ expected: Int, _ expectedWindows: [Int]) {
   let sem = DispatchSemaphore(value: 0)
   let request = KimiLocalRequest.make(port: port, token: token)!
   access.fetchKimi(request) { code, data in
    precondition(code == expected, "unexpected HTTP status \(String(describing: code))")
    if !expectedWindows.isEmpty { precondition(data.map(KimiServerQuota.parse)?.map(\.remaining) == expectedWindows) }
    sem.signal()
   }
   precondition(sem.wait(timeout: .now() + 10) == .success, "request timed out")
  }
  check("good", 200, [75, 20]); check("wrong", 401, []); check("redirect", 302, [])
  print("Kimi 로컬 HTTP 통합 검사 통과")
 }
}
