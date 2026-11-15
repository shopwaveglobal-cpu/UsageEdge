import Foundation

@main struct QuotaTests {
 static func main() {
  let json = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":2000000000},"secondary":{"usedPercent":80,"windowDurationMins":10080,"resetsAt":2000001000}}}}"#.data(using: .utf8)!
  let windows = QuotaParser.parse(json)
  precondition(windows.count == 2 && windows[0].remaining == 75 && windows[1].remaining == 20)
  let kimiAPI = Data(#"{"code":0,"data":{"kind":"ok","quota":{"usages":{"limit5h":{"usedRatio":0.25,"resetAt":"2026-11-14T12:00:00Z"},"limit7d":{"usedRatio":0.8}}}}}"#.utf8)
  let kimiWindows = KimiServerQuota.parse(kimiAPI)
  precondition(kimiWindows.map(\.remaining) == [75, 20] && kimiWindows.first?.reset != nil)
  precondition(KimiServerQuota.parse(Data(#"{"code":0,"data":{"kind":"error","quota":{"usages":{"limit5h":{"usedRatio":0}}}}}"#.utf8)).isEmpty)
  precondition(KimiServerQuota.parse(Data(#"{"code":1,"data":{"kind":"ok","quota":{"usages":{"limit5h":{"usedRatio":0}}}}}"#.utf8)).isEmpty)
  precondition(KimiServerQuota.parse(Data(#"{"code":0,"data":{"kind":"ok","quota":{"usages":{"limit5h":{"usedRatio":true}}}}}"#.utf8)).isEmpty)
  let helper = "/Users/test/Folder With Space/usageedge/claude_status.py"
  let setupData = try! JSONSerialization.data(withJSONObject: ["statusLine": ["type": "command", "command": "python3 '\(helper)'"]])
  precondition(ClaudeSetupInspector.status(setupData, helperPath: helper, helperExists: true) == .configured)
  precondition(ClaudeSetupInspector.status(setupData, helperPath: helper, helperExists: false) == .missingHelper)
  precondition(ClaudeSetupInspector.status(Data("{}".utf8), helperPath: helper, helperExists: false) == .absent)
  precondition(ClaudeSetupInspector.status(Data(#"{"statusLine":{"type":"command","command":"other"}}"#.utf8), helperPath: helper, helperExists: true) == .other)
  precondition(ClaudeSetupInspector.status(Data("{".utf8), helperPath: helper, helperExists: true) == .unreadable)
  let reference = Date(timeIntervalSince1970: 2_000_000_000)
  precondition(QuotaWindow(remaining: 50, minutes: 300, reset: reference.addingTimeInterval(1)).displayRemaining(now: reference) == 50)
  precondition(QuotaWindow(remaining: 50, minutes: 300, reset: reference).displayRemaining(now: reference) == nil)
  precondition(QuotaWindow(remaining: 50, minutes: 300, reset: reference.addingTimeInterval(-1)).displayRemaining(now: reference) == nil)
  precondition(QuotaWindow(remaining: 50, minutes: 300, reset: nil).displayRemaining(now: reference) == 50)
  precondition(QuotaWindow(remaining: 50, minutes: 300, reset: reference.addingTimeInterval(61)).resetLabel(now: reference) == "2분 후 초기화 예정")
  precondition(QuotaWindow(remaining: 50, minutes: 300, reset: reference.addingTimeInterval(-1)).resetLabel(now: reference) == "초기화 확인 중")
  precondition(QuotaWindow(remaining: 50, minutes: 300, reset: nil).resetLabel(now: reference) == "초기화 시간 확인 불가")
  precondition(QuotaParser.parse(Data("{}".utf8)).isEmpty)
  let invalid = #"{"result":{"rateLimits":{"primary":{"usedPercent":150,"windowDurationMins":300}}}}"#.data(using: .utf8)!
  precondition(QuotaParser.parse(invalid).isEmpty)
  let now = Date(timeIntervalSince1970: 2_000_000_000)
  let status = #"{"captured_at":2000000000,"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":2000003600},"seven_day":{"used_percentage":40}}}"#.data(using: .utf8)!
  let diagnostic = #"{"checked_at":2000000000,"rate_limits_present":false,"valid_window_count":0}"#.data(using: .utf8)!
  precondition(ClaudeDiagnosticParser.parse(diagnostic, now: now) == .notProvided)
  precondition(ClaudeDiagnosticParser.parse(diagnostic, now: now, notBefore: now.addingTimeInterval(1)) == nil)
  precondition(ClaudeDiagnosticParser.parse(diagnostic, now: now.addingTimeInterval(901)) == nil)
  let diagnosticInvalid = #"{"checked_at":2000000000,"rate_limits_present":true,"valid_window_count":0}"#.data(using: .utf8)!
  precondition(ClaudeDiagnosticParser.parse(diagnosticInvalid, now: now) == .noValidWindows)
  let snapshot = ClaudeStatusParser.parse(status, now: now)
  precondition(snapshot?.windows.map(\.remaining) == [77, 60] && snapshot?.capturedAt == now)
  precondition(ClaudeStatusParser.parse(status, now: now.addingTimeInterval(90000)) == nil)
  let boolUsed = #"{"result":{"rateLimits":{"primary":{"usedPercent":true,"windowDurationMins":300}}}}"#.data(using: .utf8)!
  precondition(QuotaParser.parse(boolUsed).isEmpty)
  print("Quota parser checks passed")
 }
}
