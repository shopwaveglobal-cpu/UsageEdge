import Foundation
import CoreFoundation

enum APIProvider: String, CaseIterable, Identifiable {
 case openRouter = "OpenRouter", deepSeek = "DeepSeek"
 var id: String { rawValue }
 var url: URL { URL(string: self == .openRouter ? "https://openrouter.ai/api/v1/key" : "https://api.deepseek.com/user/balance")! }
 func responseStatus(code: Int?, data: Data?) -> String {
  guard let code = code else { return "네트워크 연결 확인" }
  switch code {
  case 401, 403: return "인증 실패 · API 키 확인"
  case 429: return "요청 제한 · 잠시 후 다시 시도"
  case 500...599: return "서비스 오류 · 나중에 다시 시도"
  case 200:
   guard let data = data, data.count <= 1_000_000, let result = parse(data) else { return "응답 형식 확인 필요" }
   return result
  default: return "조회 실패 · 서비스 응답 확인"
  }
 }
 func parse(_ data: Data) -> String? {
  guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
  if self == .openRouter {
   guard let item = root["data"] as? [String: Any] else { return nil }
   func number(_ key: String) -> Double? {
    guard let n = item[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite, n.doubleValue >= 0 else { return nil }
    return n.doubleValue
   }
   if let limit = number("limit"), let remaining = number("limit_remaining") {
    return String(format: "키 한도 잔여 $%.2f / $%.2f", remaining, limit)
   }
   if item["limit"] is NSNull, let usage = number("usage") { return String(format: "키 사용 $%.2f · 한도 없음", usage) }
   return nil
  }
  guard let balances = root["balance_infos"] as? [[String: Any]] else { return nil }
  let values = balances.compactMap { item -> String? in
   guard let currency = item["currency"] as? String, ["USD", "CNY"].contains(currency),
         let value = item["total_balance"] as? String, let amount = Double(value), amount.isFinite, amount >= 0 else { return nil }
   return String(format: "%@ %.2f", currency, amount)
  }
  return values.isEmpty ? nil : "API 잔액 " + values.joined(separator: " · ")
 }
}
