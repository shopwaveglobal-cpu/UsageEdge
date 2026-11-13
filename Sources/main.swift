import AppKit
import SwiftUI
import ServiceManagement
import Combine
import UserNotifications

final class UsageModel: ObservableObject {
 @Published var windows: [QuotaWindow] = []
 @Published var status = "확인 중"
 @Published var claudeWindows: [QuotaWindow] = []
 @Published var claudeStatus = "공식 화면에서 확인"
 @Published var notificationStatus = ""
 @Published var loginInProgress = false
 var loginProcess: Process?
 var loginAttempt = LoginAttempt()
 var resize: (() -> Void)?
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
  windows = result; scheduleResets("Codex", windows: result); self.status = status
  updated = result.isEmpty ? nil : Date(); resize?()
 }
 func refresh() {
  refreshClaudeStatus()
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
  let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/UsageEdge/ClaudeStatus/snapshot.json")
  guard let data = try? Data(contentsOf: url), let snapshot = ClaudeStatusParser.parse(data), !snapshot.windows.isEmpty else {
   claudeWindows = []; claudeStatus = "공식 화면에서 확인"; scheduleResets("Claude", windows: []); return
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
      compactRow("C", color: claude, windows: model.claudeWindows)
      compactRow("D", color: codex, windows: model.windows)
     }.padding(.horizontal, 7).frame(width: 80, height: 64)
    }.buttonStyle(.plain).help("펼치기")
   }
  }
  .frame(width: model.expanded ? 210 : 80)
  .background(Color(red: 0.075, green: 0.082, blue: 0.10))
  .clipShape(RoundedRectangle(cornerRadius: 16))
  .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.09)))
 }
 func compactRow(_ name: String, color: Color, windows: [QuotaWindow]) -> some View {
  HStack(spacing: 0) {
   Text(name).font(.system(size: 9, weight: .bold)).foregroundStyle(color)
   Spacer(minLength: 0)
   ForEach([300, 10080], id: \.self) { minutes in
    Text(windows.first(where: { $0.minutes == minutes }).map { "\($0.remaining)%" } ?? "—")
     .font(.system(size: 9, weight: .medium, design: .rounded)).monospacedDigit()
     .foregroundStyle(.white.opacity(0.85)).frame(width: 25)
   }
  }.accessibilityLabel("\(name == "C" ? "Claude" : "Codex") 잔여량: 5시간 \(windows.first(where: { $0.minutes == 300 }).map { "\($0.remaining)%" } ?? "확인 불가"), 주간 \(windows.first(where: { $0.minutes == 10080 }).map { "\($0.remaining)%" } ?? "확인 불가")")
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

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
 func applicationWillTerminate(_ notification: Notification) { model?.cancelCodexLogin() }
 func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
 var panel: NSPanel!; var model: UsageModel!; var status: NSStatusItem!
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
  position(); panel.orderFrontRegardless()
  NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.position() }
 }
 @objc func toggle() { if panel.isVisible { panel.orderOut(nil) } else { position(); panel.orderFrontRegardless() } }
 func position() {
  guard let screen = NSScreen.main else { return }
  let size = panel.contentView?.fittingSize ?? NSSize(width: 258, height: 240)
  let width: CGFloat = model.expanded ? 210 : 80
  panel.setFrame(NSRect(x: screen.visibleFrame.maxX - width - 5, y: screen.visibleFrame.midY - size.height / 2, width: width, height: size.height), display: true)
 }
}
let app = NSApplication.shared
let delegate = AppDelegate(); app.delegate = delegate; app.run()
