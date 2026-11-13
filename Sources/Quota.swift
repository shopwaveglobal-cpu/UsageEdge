import Foundation
import CoreFoundation

struct QuotaWindow {
 let remaining: Int
 let minutes: Int
 let reset: Date?
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
 static func claudeCredentialExpired(_ value: Any?, now: Date = Date()) -> Bool {
  guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
  let milliseconds = number.doubleValue
  return milliseconds.isFinite && milliseconds > 0 && milliseconds / 1000 <= now.timeIntervalSince1970
 }
 static func date(_ value: Any?) -> Date? {
  guard let s = value as? String else { return nil }
  let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
 }
 static func claude(_ data: Data) -> [QuotaWindow] {
  guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
  return [("five_hour", 300), ("seven_day", 10080)].compactMap { key, mins in
   guard let item = root[key] as? [String: Any], let number = item["utilization"] as? NSNumber,
         CFGetTypeID(number) != CFBooleanGetTypeID(), let used = Double(number.stringValue),
         used.isFinite, (0...100).contains(used) else { return nil }
   return QuotaWindow(remaining: Int((100 - used).rounded()), minutes: mins, reset: date(item["resets_at"]))
  }
 }
 static func kimi(_ data: Data) -> [QuotaWindow] {
  guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
  let limits = root["limits"] as? [[String: Any]] ?? []
  var windows: [QuotaWindow] = []
  let ratios = root["usages"] as? [String: Any] ?? [:]
  for (key, mins) in [("limit_5h", 300), ("limit_7d", 10080), ("limit_month_total", -1)] {
   guard let item = ratios[key] as? [String: Any], let number = item["used_ratio"] as? NSNumber,
         CFGetTypeID(number) != CFBooleanGetTypeID(), let ratio = Double(number.stringValue), ratio.isFinite, (0...1).contains(ratio) else { continue }
   windows.append(QuotaWindow(remaining: Int(((1 - ratio) * 100).rounded(.down)), minutes: mins, reset: date(item["reset_time"])))
  }
  if windows.isEmpty, let detail = root["usage"] as? [String: Any], let l = detail["limit"] as? String, let r = detail["remaining"] as? String,
     let limit = Double(l), let rem = Double(r), limit.isFinite, rem.isFinite, limit > 0, rem >= 0, rem <= limit {
   windows.append(QuotaWindow(remaining: Int((100 * rem / limit).rounded()), minutes: 0, reset: date(detail["resetTime"])))
  }
  let counted: [QuotaWindow] = limits.compactMap { item in
   guard let window = item["window"] as? [String: Any], window["timeUnit"] as? String == "TIME_UNIT_MINUTE", let mins = window["duration"] as? Int, mins > 0,
         let detail = item["detail"] as? [String: Any], let l = detail["limit"] as? String, let r = detail["remaining"] as? String,
         let limit = Double(l), let rem = Double(r), limit.isFinite, rem.isFinite, limit > 0, rem >= 0, rem <= limit else { return nil }
   return QuotaWindow(remaining: Int((100 * rem / limit).rounded()), minutes: mins, reset: date(detail["resetTime"]))
  }
  for count in counted {
   if let i = windows.firstIndex(where: { $0.minutes == count.minutes }) {
    if let a = windows[i].reset, let b = count.reset, abs(a.timeIntervalSince(b)) <= 2, count.remaining < windows[i].remaining { windows[i] = count }
   } else { windows.append(count) }
  }
  return windows.sorted { ($0.minutes <= 0 ? Int.max : $0.minutes) < ($1.minutes <= 0 ? Int.max : $1.minutes) }
 }
}
