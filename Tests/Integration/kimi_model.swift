func waitKimi(_ predicate: () -> Bool) -> Bool {
 let deadline = Date().addingTimeInterval(5)
 while Date() < deadline { if predicate() { return true }; RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
 return predicate()
}
let model = UsageModel()
model.connectKimi(port: CommandLine.arguments[1], token: "good")
precondition(waitKimi { model.kimiStatus == "연결됨" }, "Kimi quota did not arrive: \(model.kimiStatus)")
precondition(model.kimiWindows.map(\.remaining) == [75, 20])
model.connectKimi(port: CommandLine.arguments[1], token: "wrong")
precondition(waitKimi { model.kimiStatus.contains("서버 토큰 확인 필요") })
precondition(model.kimiStatus.contains("오래된 값") && model.kimiWindows.map(\.remaining) == [75, 20])
model.connectKimi(port: CommandLine.arguments[1], token: "slow")
precondition(waitKimi { FileManager.default.fileExists(atPath: ProcessInfo.processInfo.environment["USAGEEDGE_KIMI_STARTED"]!) }, "slow request did not start")
model.disconnectKimi()
RunLoop.current.run(until: Date().addingTimeInterval(1.5))
precondition(model.kimiWindows.isEmpty && model.kimiStatus == "연결 해제됨", "late response restored disconnected account")
print("Kimi 위젯 모델 통합 검사 통과")
