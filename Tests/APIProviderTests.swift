import Foundation
@main struct APIProviderTests {
 static func main() {
  let router = #"{"data":{"limit":100,"limit_remaining":74.5,"usage":25.5}}"#.data(using: .utf8)!
  precondition(APIProvider.openRouter.parse(router) == "키 한도 잔여 $74.50 / $100.00")
  let noLimit = #"{"data":{"limit":null,"limit_remaining":null,"usage":2}}"#.data(using: .utf8)!
  precondition(APIProvider.openRouter.parse(noLimit) == "키 사용 $2.00 · 한도 없음")
  let deep = #"{"balance_infos":[{"currency":"USD","total_balance":"12.50"}]}"#.data(using: .utf8)!
  precondition(APIProvider.deepSeek.parse(deep) == "API 잔액 USD 12.50")
  precondition(APIProvider.deepSeek.parse(Data("{}".utf8)) == nil)
  precondition(APIProvider.openRouter.parse(Data(#"{"data":{"usage":true}}"#.utf8)) == nil)
  precondition(APIProvider.openRouter.responseStatus(code: 401, data: nil) == "인증 실패 · API 키 확인")
  precondition(APIProvider.openRouter.responseStatus(code: 403, data: nil) == "접근 거부 · 키 권한 확인")
  precondition(APIProvider.openRouter.responseStatus(code: 429, data: nil) == "요청 제한 · 잠시 후 다시 시도")
  precondition(APIProvider.openRouter.responseStatus(code: 503, data: nil) == "서비스 오류 · 나중에 다시 시도")
  precondition(APIProvider.openRouter.responseStatus(code: nil, data: nil) == "네트워크 연결 확인")
  precondition(APIProvider.openRouter.responseStatus(code: 200, data: Data("{}".utf8)) == "응답 형식 확인 필요")
  precondition(APIProvider.openRouter.responseStatus(code: 200, data: router) == "키 한도 잔여 $74.50 / $100.00")
  let clock = Date(timeIntervalSince1970: 1_700_000_000)
  precondition(APIProvider.retryDelay("120", now: clock) == 120)
  precondition(APIProvider.retryDelay(nil, now: clock) == 60)
  precondition(APIProvider.retryDelay("NaN", now: clock) == 60)
  precondition(APIProvider.retryDelay("9999999", now: clock) == 9999999)
  precondition(APIProvider.retryDelay("-1", now: clock) == 60)
  precondition(APIProvider.retryDelay("Tue, 14 Nov 2023 22:15:20 GMT", now: clock) == 120)
  let credit = Data(#"{"usageItems":[{"product":"Copilot AI Credits","unitType":"ai-credits","grossQuantity":12.5},{"product":"Copilot AI Credits","unitType":"ai-credits","grossQuantity":7.25}]}"#.utf8)
  precondition(CopilotBilling.parse(credit) == "이번 달 보고된 사용 19.75 크레딧")
  precondition(CopilotBilling.parse(Data(#"{"usageItems":[]}"#.utf8)) == "이번 달 청구 기록 없음")
  precondition(CopilotBilling.parse(Data(#"{"usageItems":[{"product":"Copilot AI Credits","unitType":"ai-credits","grossQuantity":true}]}"#.utf8)) == nil)
  precondition(CopilotBilling.parse(Data(#"{"usageItems":[{"product":"Other","unitType":"tokens","grossQuantity":3}]}"#.utf8)) == nil)
  precondition(CopilotBilling.validLogin("octo-cat") && !CopilotBilling.validLogin("../bad"))
  print("API 제공업체 응답 검사 통과")
 }
}
