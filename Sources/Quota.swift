import Foundation
import CoreFoundation

struct QuotaWindow {
 let remaining: Int
 let minutes: Int
 let reset: Date?
 func displayRemaining(now: Date = Date()) -> Int? {
  guard let reset = reset else { return remaining }
  let seconds = reset.timeIntervalSince(now)
  return seconds.isFinite && seconds > 0 ? remaining : nil
 }
 func resetLabel(now: Date = Date()) -> String {
  guard let reset = reset else { return "초기화 시간 확인 불가" }
  let seconds = reset.timeIntervalSince(now)
  guard seconds.isFinite else { return "초기화 시간 확인 불가" }
  guard seconds > 0 else { return "초기화 확인 중" }
  if seconds > 365 * 86400 { return "초기화 " + reset.formatted(date: .abbreviated, time: .shortened) }
  let remainingMinutes = Int(ceil(seconds / 60))
  let days = remainingMinutes / 1440, hours = (remainingMinutes % 1440) / 60, minutes = remainingMinutes % 60
  if days > 0 { return "\(days)일 \(hours)시간 후 초기화 예정" }
  if hours > 0 { return "\(hours)시간 \(minutes)분 후 초기화 예정" }
  return "\(minutes)분 후 초기화 예정"
 }
 var label: String {
  if minutes == 0 { return "기본 한도" }
  if minutes == -1 { return "월간" }
  if minutes == 300 { return "5시간" }
  if minutes == 10080 { return "주간" }
  if minutes % 1440 == 0 { return "\(minutes / 1440)일" }
  if minutes % 60 == 0 { return "\(minutes / 60)시간" }
  return "\(minutes)분"
 }
}

enum ClaudeDiagnosticParser {
 enum State { case notProvided, noValidWindows, captureFailed }
 static func parse(_ data: Data, now: Date = Date(), notBefore: Date = .distantPast) -> State? {
  guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        let timestamp = root["checked_at"] as? NSNumber, CFGetTypeID(timestamp) != CFBooleanGetTypeID(),
        timestamp.doubleValue.isFinite, timestamp.doubleValue >= notBefore.timeIntervalSince1970,
        now.timeIntervalSince1970 - timestamp.doubleValue >= -60,
        now.timeIntervalSince1970 - timestamp.doubleValue <= 900,
        let present = root["rate_limits_present"] as? NSNumber, CFGetTypeID(present) == CFBooleanGetTypeID(),
        let count = root["valid_window_count"] as? NSNumber, CFGetTypeID(count) != CFBooleanGetTypeID(),
        count.doubleValue.isFinite, count.doubleValue.rounded() == count.doubleValue,
        (0...2).contains(count.intValue) else { return nil }
  if !present.boolValue { return .notProvided }
  return count.intValue == 0 ? .noValidWindows : .captureFailed
 }
}

enum ClaudeStatusParser {
 static func parse(_ data: Data, now: Date = Date()) -> (windows: [QuotaWindow], capturedAt: Date)? {
  guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        let timestamp = root["captured_at"] as? NSNumber, CFGetTypeID(timestamp) != CFBooleanGetTypeID(),
        timestamp.doubleValue.isFinite else { return nil }
  let capturedAt = Date(timeIntervalSince1970: timestamp.doubleValue)
  guard now.timeIntervalSince(capturedAt) >= -60, now.timeIntervalSince(capturedAt) <= 86400,
        let rate = root["rate_limits"] as? [String: Any] else { return nil }
  let windows: [QuotaWindow] = [("five_hour", 300), ("seven_day", 10080)].compactMap { key, minutes in
   guard let item = rate[key] as? [String: Any], let number = item["used_percentage"] as? NSNumber,
         CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
         (0...100).contains(number.doubleValue) else { return nil }
   let reset = (item["resets_at"] as? NSNumber).flatMap { n -> Date? in
    guard CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite, n.doubleValue > 0, n.doubleValue < 253402300800 else { return nil }
    return Date(timeIntervalSince1970: n.doubleValue)
   }
   return QuotaWindow(remaining: Int((100 - number.doubleValue).rounded()), minutes: minutes, reset: reset)
  }
  return (windows, capturedAt)
 }
}

enum QuotaParser {
 static func parse(_ data: Data) -> [QuotaWindow] {
  guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        let result = root["result"] as? [String: Any],
        let limits = result["rateLimits"] as? [String: Any] else { return [] }
  return ["primary", "secondary"].compactMap { key in
   guard let w = limits[key] as? [String: Any], let number = w["usedPercent"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
         let used = Double(number.stringValue), used.isFinite, (0...100).contains(used), let minutes = w["windowDurationMins"] as? Int, minutes > 0 else { return nil }
   let reset = (w["resetsAt"] as? Double).flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0) : nil }
   return QuotaWindow(remaining: Int((100 - used).rounded()), minutes: minutes, reset: reset)
  }
 }
}

enum ProviderParser {
 static func date(_ value: Any?) -> Date? {
  guard let s = value as? String else { return nil }
  let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
 }

}

// Kimi Code's local server API is experimental and can change between versions.
enum KimiServerQuota {
 static func parse(_ data: Data) -> [QuotaWindow] {
  guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        let code = root["code"] as? NSNumber, CFGetTypeID(code) != CFBooleanGetTypeID(), code.doubleValue == 0,
        let body = root["data"] as? [String: Any], body["kind"] as? String == "ok",
        let quota = body["quota"] as? [String: Any], let usages = quota["usages"] as? [String: Any] else { return [] }
  return [("limit5h", 300), ("limit7d", 10080)].compactMap { key, minutes in
   guard let item = usages[key] as? [String: Any], let ratio = item["usedRatio"] as? NSNumber,
         CFGetTypeID(ratio) != CFBooleanGetTypeID(), ratio.doubleValue.isFinite,
         (0...1).contains(ratio.doubleValue) else { return nil }
   return QuotaWindow(remaining: Int(((1 - ratio.doubleValue) * 100).rounded()), minutes: minutes, reset: ProviderParser.date(item["resetAt"]))
  }
 }
}

enum ClaudeSetupInspector {
 enum State { case configured, missingHelper, absent, other, unreadable }
 static func status(_ data: Data, helperPath: String, helperExists: Bool) -> State {
  guard data.count <= 1_000_000,
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .unreadable }
  guard let raw = root["statusLine"] else { return .absent }
  let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-")
  let quoted = helperPath.unicodeScalars.allSatisfy { safe.contains($0) } && !helperPath.isEmpty
   ? helperPath : "'" + helperPath.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
  guard let line = raw as? [String: Any], line["type"] as? String == "command",
        line["command"] as? String == "python3 " + quoted else { return .other }
  return helperExists ? .configured : .missingHelper
 }
}
