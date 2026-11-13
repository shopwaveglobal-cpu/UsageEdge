
func waitFor(_ predicate: () -> Bool) -> Bool {
 let deadline = Date().addingTimeInterval(5)
 while Date() < deadline { if predicate() { return true }; RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
 return predicate()
}
let claude = UsageModel(); claude.refreshClaudeStatus()
precondition(claude.claudeWindows.map(\.remaining) == [75, 20], "Claude status capture did not reach the widget model")
precondition(claude.claudeStatus.hasSuffix("기준"), "Claude snapshot time is missing: \(claude.claudeStatus)")
let snapshotURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["USAGEEDGE_FAKE_SNAPSHOT"]!)
var snapshot = try! JSONSerialization.jsonObject(with: Data(contentsOf: snapshotURL)) as! [String: Any]
snapshot["captured_at"] = Date().timeIntervalSince1970 - 901
try! JSONSerialization.data(withJSONObject: snapshot).write(to: snapshotURL)
claude.refreshClaudeStatus()
precondition(claude.claudeStatus == "오래된 값", "old Claude data was not marked stale")
snapshot["captured_at"] = Date().timeIntervalSince1970 - 86401
try! JSONSerialization.data(withJSONObject: snapshot).write(to: snapshotURL)
claude.refreshClaudeStatus()
precondition(claude.claudeWindows.isEmpty, "expired Claude data remained visible")
func scenario(_ mode: String, expected: String, shouldOpen: Bool) {
 setenv("USAGEEDGE_FAKE_MODE", mode, 1); testOpened.removeAll()
 let model = UsageModel(); model.connectCodex()
 precondition(waitFor { !model.loginInProgress }, "\(mode) timed out")
 precondition(model.status == expected, "\(mode): \(model.status)")
 precondition((!testOpened.isEmpty) == shouldOpen, "\(mode): browser state")
}
scenario("success", expected: "확인 중", shouldOpen: true)
scenario("failure", expected: "로그인 미완료 · 다시 시도", shouldOpen: true)
scenario("wronghost", expected: "로그인 미완료 · 다시 시도", shouldOpen: false)
 scenario("earlyexit", expected: "로그인 미완료 · 다시 시도", shouldOpen: false)
setenv("USAGEEDGE_FAKE_MODE", "cancel", 1); testOpened.removeAll()
let model = UsageModel(); model.connectCodex()
precondition(waitFor { !testOpened.isEmpty }, "cancel: login did not start")
model.cancelCodexLogin(); RunLoop.current.run(until: Date().addingTimeInterval(0.3))
precondition(!model.loginInProgress && model.status == "로그인 취소됨")
let marker = NSTemporaryDirectory() + "usageedge-race-" + UUID().uuidString
setenv("USAGEEDGE_FAKE_MARKER", marker, 1); setenv("USAGEEDGE_FAKE_MODE", "race", 1)
let race = UsageModel(); race.refresh()
precondition(waitFor { FileManager.default.fileExists(atPath: marker) }, "race: refresh did not start")
race.connectCodex()
precondition(waitFor { !race.loginInProgress }, "race: login did not finish")
precondition(waitFor { !race.busy && race.windows.first?.remaining == 75 }, "race: login did not trigger fresh quota")
try? FileManager.default.removeItem(atPath: marker)
print("모의 로그인 통합 검사 통과")
