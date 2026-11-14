import AppKit
import SwiftUI
import ServiceManagement
import Combine
import UserNotifications

final class UsageModel: ObservableObject {
 @Published var windows: [QuotaWindow] = []
 @Published var status = "확인 중"
 @Published var claudeWindows: [QuotaWindow] = []
 @Published var claudeStatus = "설정에서 연결"
 @Published var notificationStatus = ""
 @Published var claudeSetupStatus = "Claude Code 연결 전"
 @Published var apiStatuses: [String: String] = [:]
 @Published var kimiWindows: [QuotaWindow] = []
 @Published var kimiStatus = "연결 전"
 private var kimiVersion = 0
 private let providerAccess = ProviderAccess()
 private var apiVersions: [String: Int] = [:]
 @Published var loginInProgress = false
 var loginProcess: Process?
 var loginAttempt = LoginAttempt()
 var resize: (() -> Void)?
 var openSettings: (() -> Void)?
 @Published var updated: Date?
 @Published var expanded = true
 @Published var loginEnabled = SMAppService.mainApp.status == .enabled
 @Published var interval: Int = UserDefaults.standard.integer(forKey: "interval") == 0 ? 300 : UserDefaults.standard.integer(forKey: "interval")
 var timer: Timer?
 var busy = false
 var refreshPending = false
 init() { schedule(); refresh() }
 func schedule() {
  timer?.invalidate()
  UserDefaults.standard.set(interval, forKey: "interval")
  timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval), repeats: true) { [weak self] _ in self?.refresh() }
 }
 func setLogin(_ enabled: Bool) {
  do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
  catch { status = "로그인 항목 설정 실패" }
  loginEnabled = SMAppService.mainApp.status == .enabled
 }
 func connectCodex() {
  guard !loginInProgress else { return }
  let paths = ["/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
  guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { status = "Codex CLI 설치 필요"; return }
  refreshPending = false; loginInProgress = true; status = "브라우저 연결 준비 중"
  let attempt = loginAttempt.begin()
  let process = Process(); process.executableURL = URL(fileURLWithPath: path); process.arguments = ["app-server", "--stdio"]
  loginProcess = process
  DispatchQueue.global(qos: .utility).async {
   let input = Pipe(), output = Pipe(); process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
   var result = false
   do {
    guard DispatchQueue.main.sync(execute: { self.loginAttempt.isCurrent(attempt) }) else {
     DispatchQueue.main.async { if self.loginProcess === process { self.loginProcess = nil } }
     return
    }
    try process.run()
    if !DispatchQueue.main.sync(execute: { self.loginAttempt.isCurrent(attempt) }) {
     if process.isRunning { process.terminate() }; process.waitUntilExit()
     DispatchQueue.main.async { if self.loginProcess === process { self.loginProcess = nil } }
     return
    }
    let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + 300, execute: timeout)
    func send(_ string: String) { input.fileHandleForWriting.write(Data((string + "\n").utf8)) }
    send("{\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"usage_edge\",\"version\":\"1.0\"}}}")
    var buffer = Data(); var loginID: String?; var finished = false
    while process.isRunning && !finished {
     let data = output.fileHandleForReading.availableData
     if data.isEmpty { break }; buffer.append(data)
     while let newline = buffer.firstIndex(of: 10) {
      let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
      guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
      if object["id"] as? Int == 1 {
       guard object["error"] == nil else { finished = true; break }
       send("{\"method\":\"initialized\"}")
       send("{\"id\":3,\"method\":\"account/login/start\",\"params\":{\"type\":\"chatgpt\"}}")
      } else if object["id"] as? Int == 3 {
       guard let start = CodexAuth.parseStart(line) else { finished = true; break }
       loginID = start.loginID
       DispatchQueue.main.async {
        guard self.loginAttempt.isCurrent(attempt) else { if process.isRunning { process.terminate() }; return }
        self.status = "브라우저에서 로그인 중"
        if !NSWorkspace.shared.open(start.url), process.isRunning { process.terminate() }
       }
      } else if let loginID = loginID, let success = CodexAuth.parseCompletion(line, loginID: loginID) {
       result = success; finished = true; break
      }
     }
     if buffer.count > 1_000_000 { break }
    }
    timeout.cancel(); if process.isRunning { process.terminate() }; process.waitUntilExit()
   } catch { }
   let success = result
   DispatchQueue.main.async {
    if self.loginProcess === process { self.loginProcess = nil }
    guard self.loginAttempt.finish(attempt) else { return }
    self.loginInProgress = false
    if success {
     self.status = "로그인 완료 · 사용량 확인 중"
     if self.busy { self.refreshPending = true } else { self.refresh() }
    }
    else { self.status = "로그인 미완료 · 다시 시도" }
   }
  }
 }
 func cancelCodexLogin() {
  loginAttempt.cancel(); loginInProgress = false; status = "로그인 취소됨"
  if let process = loginProcess, process.isRunning { process.terminate() }
 }
 func completeRefresh(_ result: [QuotaWindow], status: String) {
  busy = false
  if loginInProgress { return }
  if refreshPending { refreshPending = false; refresh(); return }
  guard !result.isEmpty else {
   self.status = windows.isEmpty ? status : "오래된 값 · " + status
   resize?(); return
  }
  windows = result; scheduleResets("Codex", windows: result); self.status = status
  updated = Date(); resize?()
 }
 func refresh() {
  refreshClaudeStatus()
  if UserDefaults.standard.bool(forKey: "kimi.enabled") { refreshKimi() }
  for provider in APIProvider.allCases where UserDefaults.standard.bool(forKey: "enabled.\(provider.rawValue)") { refreshAPI(provider) }
  guard !busy, !loginInProgress else { return }; busy = true; status = "확인 중"

  DispatchQueue.global(qos: .utility).async {
   let paths = ["/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
   guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
    DispatchQueue.main.async { self.completeRefresh([], status: "Codex CLI를 찾을 수 없음") }; return
   }
   let process = Process(); process.executableURL = URL(fileURLWithPath: path); process.arguments = ["app-server", "--stdio"]
   let input = Pipe(), output = Pipe(); process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
   do {
    try process.run()
    let requests = ["{\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"usage_edge\",\"version\":\"1.0\"}}}", "{\"method\":\"initialized\"}", "{\"id\":2,\"method\":\"account/rateLimits/read\"}"]
    input.fileHandleForWriting.write(Data((requests.joined(separator: "\n") + "\n").utf8))
    let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: timeout)
    var buffer = Data(); var result: [QuotaWindow] = []; var responseReceived = false
    while process.isRunning {
     let data = output.fileHandleForReading.availableData
     if data.isEmpty { break }; buffer.append(data)
     while let newline = buffer.firstIndex(of: 10) {
      let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
      if let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], object["id"] as? Int == 2 {
       result = QuotaParser.parse(line); responseReceived = true; break
      }
     }
     if responseReceived { break }
     if buffer.count > 1_000_000 { break }
    }
    timeout.cancel(); if process.isRunning { process.terminate() }; process.waitUntilExit()
    DispatchQueue.main.async { self.completeRefresh(result, status: result.isEmpty ? "확인 불가 · 로그인 또는 연결 확인" : "연결됨") }
   } catch { DispatchQueue.main.async { self.completeRefresh([], status: "실행 실패") } }
  }
 }
 func refreshClaudeStatus() {
  if UserDefaults.standard.bool(forKey: "claude.disconnected") {
   claudeWindows = []; claudeStatus = "연결 해제됨"; scheduleResets("Claude", windows: []); resize?(); return
  }
  let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/UsageEdge/ClaudeStatus/snapshot.json")
  guard let data = try? Data(contentsOf: url), let snapshot = ClaudeStatusParser.parse(data), !snapshot.windows.isEmpty else {
   claudeWindows = []; claudeStatus = "설정에서 연결"; scheduleResets("Claude", windows: []); return
  }
  guard snapshot.capturedAt.timeIntervalSince1970 >= UserDefaults.standard.double(forKey: "claude.minimumCapture") else {
   claudeWindows = []; claudeStatus = "새 사용량 대기 중"; scheduleResets("Claude", windows: []); resize?(); return
  }
  claudeWindows = snapshot.windows
  claudeStatus = Date().timeIntervalSince(snapshot.capturedAt) > 900 ? "오래된 값" : snapshot.capturedAt.formatted(date: .omitted, time: .shortened) + " 기준"
  scheduleResets("Claude", windows: snapshot.windows); resize?()
 }
 func scheduleResets(_ provider: String, windows: [QuotaWindow]) {
  let center = UNUserNotificationCenter.current()
  let ids = ["\(provider).300", "\(provider).10080"]
  center.removePendingNotificationRequests(withIdentifiers: ids)
  for window in windows where (window.minutes == 300 || window.minutes == 10080) {
   guard let date = window.reset, date.timeIntervalSinceNow > 1 else { continue }
   let content = UNMutableNotificationContent()
   content.title = "\(provider) 사용량 초기화"
   content.body = "\(window.label) 한도의 초기화 예정 시각입니다. 앱에서 최신 상태를 확인하세요."
   content.sound = .default
   let trigger = UNTimeIntervalNotificationTrigger(timeInterval: date.timeIntervalSinceNow, repeats: false)
   center.add(UNNotificationRequest(identifier: "\(provider).\(window.minutes)", content: content, trigger: trigger))
  }
 }
 func testNotification() {
  let center = UNUserNotificationCenter.current()
  center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
   guard granted else { DispatchQueue.main.async { self.notificationStatus = "알림 권한 확인 필요" }; return }
   DispatchQueue.main.async { self.notificationStatus = "" }
   let content = UNMutableNotificationContent()
   content.title = "UsageEdge 알림 테스트"
   content.body = "초기화 알림이 이 방식으로 표시됩니다."
   content.sound = .default
   center.removeDeliveredNotifications(withIdentifiers: ["test"])
   center.add(UNNotificationRequest(identifier: "test", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)))
   DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
    center.getDeliveredNotifications { delivered in
     DispatchQueue.main.async { self.notificationStatus = delivered.contains(where: { $0.request.identifier == "test" }) ? "테스트 알림 전달됨" : "알림 전달 확인 필요" }
    }
   }
  }
 }
 func checkScheduledNotifications() {
  UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
   let count = requests.filter { $0.identifier.hasPrefix("Claude.") || $0.identifier.hasPrefix("Codex.") }.count
   DispatchQueue.main.async { self.notificationStatus = "초기화 알림 \(count)개 예약됨" }
  }
 }
 func connectClaude() {
  if let url = URL(string: "https://claude.ai/settings/usage") { NSWorkspace.shared.open(url) }
 }
 func setupClaude(disconnect: Bool = false) {
  guard let script = Bundle.main.url(forResource: "setup_claude", withExtension: "py") else {
   claudeSetupStatus = "연결 도구를 찾을 수 없습니다"; return
  }
  claudeSetupStatus = "연결 설정 중"
  DispatchQueue.global(qos: .utility).async {
   let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
   process.arguments = [script.path, disconnect ? "--uninstall" : "--install"]; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
   do {
    try process.run(); process.waitUntilExit()
    let success = process.terminationStatus == 0
    DispatchQueue.main.async {
     self.claudeSetupStatus = success ? (disconnect ? "연결 해제됨 · Claude Code 재시작 필요" : "연결됨 · Claude Code 사용 후 갱신") : "설정 실패 · 기존 상태줄과 권한 확인"
     if success {
      if !disconnect { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "claude.minimumCapture") }
      UserDefaults.standard.set(disconnect, forKey: "claude.disconnected")
     }
     self.refreshClaudeStatus()
    }
   } catch { DispatchQueue.main.async { self.claudeSetupStatus = "연결 도구 실행 실패" } }
  }
 }
 func connectKimi(port: String, token: String) {
  guard let number = Int(port), KimiLocalRequest.make(port: number, token: token) != nil else { kimiStatus = "포트와 토큰 확인 필요"; return }
  guard providerAccess.save(token, account: "KimiCodeLocal") else { kimiStatus = "키체인 저장 실패"; return }
  UserDefaults.standard.set(number, forKey: "kimi.port")
  UserDefaults.standard.set(true, forKey: "kimi.enabled")
  refreshKimi()
 }
 func disconnectKimi() {
  guard providerAccess.remove(account: "KimiCodeLocal") else { kimiStatus = "키체인 삭제 실패"; return }
  UserDefaults.standard.set(false, forKey: "kimi.enabled"); kimiVersion += 1
  kimiWindows = []; kimiStatus = "연결 해제됨"; scheduleResets("Kimi", windows: []); resize?()
 }
 func refreshKimi() {
  kimiVersion += 1; let version = kimiVersion
  guard let token = providerAccess.key(account: "KimiCodeLocal"),
        let request = KimiLocalRequest.make(port: UserDefaults.standard.integer(forKey: "kimi.port"), token: token) else { kimiStatus = "연결 설정 확인 필요"; return }
  kimiStatus = "확인 중"
  providerAccess.fetchKimi(request) { code, data in
   let result = (code == 200 && (data?.count ?? 0) <= 1_000_000) ? data.map(KimiServerQuota.parse) ?? [] : []
   DispatchQueue.main.async {
    guard self.kimiVersion == version else { return }
    guard !result.isEmpty else {
     let reason = code == 401 ? "서버 토큰 확인 필요" : "조회 불가 · 서버와 로그인 확인"
     self.kimiStatus = self.kimiWindows.isEmpty ? reason : "오래된 값 · " + reason
     return
    }
    self.kimiWindows = result; self.kimiStatus = "연결됨"; self.scheduleResets("Kimi", windows: result); self.resize?()
   }
  }
 }
 func saveAPI(_ provider: APIProvider, key: String) {
  let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !cleaned.isEmpty, !cleaned.contains(where: { $0.isWhitespace || $0.isNewline }) else { apiStatuses[provider.rawValue] = "API 키를 확인하세요"; return }
  guard providerAccess.save(cleaned, for: provider) else { apiStatuses[provider.rawValue] = "키체인 저장 실패"; return }
  UserDefaults.standard.set(true, forKey: "enabled.\(provider.rawValue)")
  refreshAPI(provider)
 }
 func disconnectAPI(_ provider: APIProvider) {
  guard providerAccess.remove(provider) else { apiStatuses[provider.rawValue] = "키체인 삭제 실패"; return }
  UserDefaults.standard.removeObject(forKey: "enabled.\(provider.rawValue)")
  apiVersions[provider.rawValue, default: 0] += 1; apiStatuses.removeValue(forKey: provider.rawValue); resize?()
 }
 func refreshAPI(_ provider: APIProvider) {
  apiVersions[provider.rawValue, default: 0] += 1
  let version = apiVersions[provider.rawValue]!
  guard let key = providerAccess.key(provider) else { apiStatuses[provider.rawValue] = "키체인 연결 확인 필요"; return }
  apiStatuses[provider.rawValue] = "조회 중"
  providerAccess.fetch(provider, key: key) { result in
   DispatchQueue.main.async {
    guard self.apiVersions[provider.rawValue] == version else { return }
    self.apiStatuses[provider.rawValue] = result; self.resize?()
   }
  }
 }

}

struct WidgetView: View {
 @ObservedObject var model: UsageModel
 var resize: () -> Void
 let claude = Color(red: 0.91, green: 0.61, blue: 0.46)
 let codex = Color(red: 0.43, green: 0.83, blue: 0.69)
 var body: some View {
  VStack(spacing: 0) {
   if model.expanded {
    HStack(alignment: .center) {
     Text("USAGE").font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(.white.opacity(0.65))
     Spacer()
     Button(action: { model.refresh() }) { Image(systemName: "arrow.clockwise") }.help("새로고침")
     Button(action: { model.expanded = false; resize() }) { Image(systemName: "chevron.right") }.help("접기")
    }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.65)).padding(.horizontal, 12).padding(.vertical, 10)
    VStack(spacing: 6) {
     quotaProvider("Claude", color: claude, status: model.claudeStatus, windows: model.claudeWindows)
     quotaProvider("Codex", color: codex, status: model.status, windows: model.windows)
     if !model.kimiWindows.isEmpty { quotaProvider("Kimi Code", color: .orange, status: model.kimiStatus, windows: model.kimiWindows) }
     ForEach(APIProvider.allCases) { provider in
      if let value = model.apiStatuses[provider.rawValue] {
       VStack(alignment: .leading, spacing: 4) {
        Text(provider.rawValue).font(.system(size: 11, weight: .semibold))
        Text(value).font(.system(size: 9)).foregroundStyle(.white.opacity(0.7))
       }.frame(maxWidth: .infinity, alignment: .leading).padding(8).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
      }
     }
    }.padding(.horizontal, 7)
    HStack {
     Text(model.notificationStatus.isEmpty ? (model.updated.map { "갱신 " + $0.formatted(date: .omitted, time: .shortened) } ?? "갱신 대기 중") : model.notificationStatus)
     Spacer()
     settings
    }.font(.system(size: 9)).foregroundStyle(.white.opacity(0.45)).padding(.horizontal, 12).padding(.vertical, 8)
   } else {
    Button(action: { model.expanded = true; resize() }) {
     VStack(spacing: 5) {
      HStack(spacing: 0) {
       Image(systemName: "chevron.left").font(.system(size: 8, weight: .semibold))
       Spacer()
       Text("5H").frame(width: 25)
       Text("주").frame(width: 25)
      }.font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.45))
      compactRow("Claude", symbol: "C", color: claude, status: model.claudeStatus, windows: model.claudeWindows)
      compactRow("Codex", symbol: "D", color: codex, status: model.status, windows: model.windows)
      if !model.kimiWindows.isEmpty { compactRow("Kimi Code", symbol: "K", color: .orange, status: model.kimiStatus, windows: model.kimiWindows) }
     }.padding(.horizontal, 7).frame(width: 80, height: model.kimiWindows.isEmpty ? 64 : 80)
    }.buttonStyle(.plain).help("펼치기")
   }
  }
  .frame(width: model.expanded ? 210 : 80)
  .background(Color(red: 0.075, green: 0.082, blue: 0.10))
  .clipShape(RoundedRectangle(cornerRadius: 16))
  .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.09)))
 }
 func compactRow(_ name: String, symbol: String, color: Color, status: String, windows: [QuotaWindow]) -> some View {
  HStack(spacing: 0) {
   Text(symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(color)
   Spacer(minLength: 0)
   ForEach([300, 10080], id: \.self) { minutes in
    Text(status.contains("오래된 값") ? "—" : (windows.first(where: { $0.minutes == minutes }).map { "\($0.remaining)%" } ?? "—"))
     .font(.system(size: 9, weight: .medium, design: .rounded)).monospacedDigit()
     .foregroundStyle(.white.opacity(0.85)).frame(width: 25)
   }
  }.accessibilityLabel("\(name) 잔여량 (\(status)): 5시간 \(windows.first(where: { $0.minutes == 300 }).map { "\($0.remaining)%" } ?? "확인 불가"), 주간 \(windows.first(where: { $0.minutes == 10080 }).map { "\($0.remaining)%" } ?? "확인 불가")")
 }
 func quotaProvider(_ name: String, color: Color, status: String, windows: [QuotaWindow]) -> some View {
  VStack(alignment: .leading, spacing: 6) {
   HStack {
    Circle().fill(color).frame(width: 7, height: 7)
    Text(name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.93))
    Spacer()
    Text(status == "연결됨" ? "LIVE" : status).font(.system(size: 9, weight: .medium)).foregroundStyle(status == "연결됨" ? color.opacity(0.8) : .white.opacity(0.5)).lineLimit(1)
   }
   ForEach(Array(windows.enumerated()), id: \.offset) { _, w in
    VStack(alignment: .leading, spacing: 3) {
     HStack(alignment: .firstTextBaseline) {
      Text(w.label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.58))
      Spacer()
      Text("\(w.remaining)%").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white)
      Text("남음").font(.system(size: 9)).foregroundStyle(.white.opacity(0.42))
     }
     GeometryReader { geo in
      ZStack(alignment: .leading) {
       Capsule().fill(.white.opacity(0.08))
       Capsule().fill(color.opacity(0.9)).frame(width: geo.size.width * CGFloat(w.remaining) / 100)
      }
     }.frame(height: 3)
     TimelineView(.periodic(from: .now, by: 60)) { context in
      Text(w.resetLabel(now: context.date))
       .font(.system(size: 9)).foregroundStyle(.white.opacity(0.52)).frame(maxWidth: .infinity, alignment: .trailing)
       .help(w.reset.map { "초기화 예정 " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "초기화 시간 확인 불가")
     }
    }
   }
  }.padding(8).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
 }
 var settings: some View {
  Menu {
   Button("서비스 설정…") { model.openSettings?() }
   Button("지금 새로고침") { model.refresh() }
   Button("Codex 브라우저 연결…") { model.connectCodex() }.disabled(model.loginInProgress)
   if model.loginInProgress { Button("Codex 연결 취소") { model.cancelCodexLogin() } }
   Button("Claude 사용량 열기") { model.connectClaude() }
   Picker("자동 새로고침", selection: $model.interval) { Text("5분").tag(300); Text("10분").tag(600); Text("30분").tag(1800) }.onChange(of: model.interval) { _ in model.schedule() }
   Toggle("로그인 시 실행", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
   Button("알림 테스트") { model.testNotification() }
   Button("예약 알림 확인") { model.checkScheduledNotifications() }
   Button("알림 설정 열기") { if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) } }
   Divider()
   Button("종료") { NSApplication.shared.terminate(nil) }
  } label: { Image(systemName: "gearshape") }.menuStyle(.borderlessButton).fixedSize().help("설정")
 }
}

struct SettingsView: View {
 @ObservedObject var model: UsageModel
 @State private var openRouterKey = ""
 @State private var deepSeekKey = ""
 @State private var kimiPort = "58627"
 @State private var kimiToken = ""
 var body: some View {
  ScrollView { VStack(alignment: .leading, spacing: 16) {
   Text("서비스 설정").font(.title2.bold())
   GroupBox("Claude Code") {
    VStack(alignment: .leading, spacing: 8) {
     Text(model.claudeSetupStatus).font(.caption)
     Text("Claude Code 사용 중 받은 사용량을 표시합니다. 기존 상태줄이 있으면 변경하지 않습니다.").font(.caption).foregroundStyle(.secondary)
     HStack { Button("Claude Code 연결") { model.setupClaude() }; Button("연결 해제") { model.setupClaude(disconnect: true) }; Button("공식 사용량 열기") { model.connectClaude() } }
    }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
   }
   GroupBox("Codex") {
    HStack { Text(model.status).font(.caption); Spacer(); Button("브라우저 연결") { model.connectCodex() }.disabled(model.loginInProgress) }.padding(4)
   }
   GroupBox("Gemini CLI") {
    VStack(alignment: .leading, spacing: 6) {
     Text("자동 조회 준비 중 · Gemini 웹 구독과 별도").font(.caption)
     Text("Gemini CLI에서 /stats model을 실행하면 지원 모델의 사용량과 한도를 확인할 수 있습니다.").font(.caption)
     Button("명령어 복사") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("/stats model", forType: .string) }
    }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
   }
   GroupBox("Kimi Code") {
    VStack(alignment: .leading) {
     Text(model.kimiStatus).font(.caption)
     Text("로그인된 Kimi Code 로컬 서버의 포트와 서버 토큰을 입력하세요. 토큰은 해당 서버의 파일 및 명령 기능에도 접근할 수 있습니다.").font(.caption)
     TextField("포트", text: $kimiPort)
     SecureField("로컬 서버 토큰", text: $kimiToken)
     HStack { Button("연결") { let token = kimiToken; kimiToken = ""; model.connectKimi(port: kimiPort, token: token) }; Button("연결 해제") { model.disconnectKimi() } }
    }.padding(4)
   }
   apiSettings(.openRouter, key: $openRouterKey)
   apiSettings(.deepSeek, key: $deepSeekKey)
   Spacer()
  }.padding(20) }.frame(width: 450, height: 440)
 }
 func apiSettings(_ provider: APIProvider, key: Binding<String>) -> some View {
  GroupBox(provider.rawValue + " API") {
   VStack(alignment: .leading, spacing: 6) {
    Text(model.apiStatuses[provider.rawValue] ?? "연결 전").font(.caption)
    SecureField("API 키", text: key)
    HStack {
     Button("키 저장 및 조회") { let value = key.wrappedValue; key.wrappedValue = ""; model.saveAPI(provider, key: value) }
     Button("키 삭제") { model.disconnectAPI(provider) }
    }
    Text("키는 이 Mac의 키체인에 저장되며 해당 서비스에만 전송됩니다.").font(.caption2).foregroundStyle(.secondary)
   }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
  }
 }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
 func applicationWillTerminate(_ notification: Notification) { model?.cancelCodexLogin() }
 func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
 var panel: NSPanel!; var model: UsageModel!; var status: NSStatusItem!
 var settingsWindow: NSWindow?
 func applicationDidFinishLaunching(_ notification: Notification) {
  NSApp.setActivationPolicy(.accessory)
  UNUserNotificationCenter.current().delegate = self
  UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
  model = UsageModel()
  panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 258, height: 320), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
  panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.level = .floating
  panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
  panel.contentView = NSHostingView(rootView: WidgetView(model: model, resize: { [weak self] in self?.position() }))
  status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength); status.button?.title = "◔"; status.button?.target = self; status.button?.action = #selector(toggle)
  model.resize = { [weak self] in self?.position() }
  model.openSettings = { [weak self] in self?.showSettings() }
  position(); panel.orderFrontRegardless()
  NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.position() }
 }
 @objc func toggle() { if panel.isVisible { panel.orderOut(nil) } else { position(); panel.orderFrontRegardless() } }
 func showSettings() {
  if settingsWindow == nil {
   let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 440), styleMask: [.titled, .closable], backing: .buffered, defer: false)
   window.title = "UsageEdge 설정"; window.isReleasedWhenClosed = false
   window.contentView = NSHostingView(rootView: SettingsView(model: model)); window.center(); settingsWindow = window
  }
  settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
 }
 func position() {
  guard let screen = NSScreen.main else { return }
  let size = panel.contentView?.fittingSize ?? NSSize(width: 258, height: 240)
  let width: CGFloat = model.expanded ? 210 : 80
  panel.setFrame(NSRect(x: screen.visibleFrame.maxX - width - 5, y: screen.visibleFrame.midY - size.height / 2, width: width, height: size.height), display: true)
 }
}
let app = NSApplication.shared
let delegate = AppDelegate(); app.delegate = delegate; app.run()
