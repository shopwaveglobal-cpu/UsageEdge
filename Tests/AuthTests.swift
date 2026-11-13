import Foundation

@main struct AuthTests {
 static func main() {
  let start = #"{"id":3,"result":{"type":"chatgpt","loginId":"login-1","authUrl":"https://chatgpt.com/auth/start?state=example"}}"#.data(using: .utf8)!
  precondition(CodexAuth.parseStart(start)?.loginID == "login-1")
  let wrongHost = #"{"id":3,"result":{"type":"chatgpt","loginId":"login-1","authUrl":"https://evil.example/login"}}"#.data(using: .utf8)!
  precondition(CodexAuth.parseStart(wrongHost) == nil)
  let http = #"{"id":3,"result":{"type":"chatgpt","loginId":"login-1","authUrl":"http://chatgpt.com/login"}}"#.data(using: .utf8)!
  precondition(CodexAuth.parseStart(http) == nil)
  let disguised = #"{"id":3,"result":{"type":"chatgpt","loginId":"login-1","authUrl":"https://chatgpt.com.evil.example/login"}}"#.data(using: .utf8)!
  precondition(CodexAuth.parseStart(disguised) == nil)
  let missingID = #"{"id":3,"result":{"type":"chatgpt","authUrl":"https://chatgpt.com/login"}}"#.data(using: .utf8)!
  precondition(CodexAuth.parseStart(missingID) == nil)
  let completed = #"{"method":"account/login/completed","params":{"loginId":"login-1","success":true}}"#.data(using: .utf8)!
  precondition(CodexAuth.parseCompletion(completed, loginID: "login-1") == true)
  precondition(CodexAuth.parseCompletion(completed, loginID: "different") == nil)
  let declined = #"{"method":"account/login/completed","params":{"loginId":"login-1","success":false}}"#.data(using: .utf8)!
  precondition(CodexAuth.parseCompletion(declined, loginID: "login-1") == false)
  let badBoolean = #"{"method":"account/login/completed","params":{"loginId":"login-1","success":1}}"#.data(using: .utf8)!
  precondition(CodexAuth.parseCompletion(badBoolean, loginID: "login-1") == nil)
  var attempt = LoginAttempt()
  let first = attempt.begin()
  precondition(attempt.isCurrent(first))
  attempt.cancel()
  precondition(!attempt.isCurrent(first))
  let second = attempt.begin()
  precondition(attempt.isCurrent(second) && !attempt.isCurrent(first))
  precondition(!attempt.finish(first) && attempt.isCurrent(second))
  precondition(attempt.finish(second) && !attempt.isCurrent(second))
  print("인증 응답 검사 통과")
 }
}
