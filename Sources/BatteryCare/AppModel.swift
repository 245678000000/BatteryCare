import SwiftUI
import Observation
import ServiceManagement
import UniformTypeIdentifiers
import Shared

@Observable
final class AppModel {
    static let shared = AppModel()

    var prefs: Prefs {
        didSet {
            guard prefs != oldValue else { return }
            prefs.save()
            prefsChanged(from: oldValue)
        }
    }
    var battery = BatterySnapshot()
    var helper: HelperStatus?
    var helperRunning = false
    var helperInstalled = false
    var history: [HistoryPoint] = []
    var selection: Page = .dashboard
    var processes: [ProcInfo] = []
    var overlayVisible = false
    var overlayEditing = false
    var showHelperSheet = false
    var launchAtLogin = SMAppService.mainApp.status == .enabled
    var alert: String?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastPushed: ControlState?
    @ObservationIgnored private var lastPush = Date.distantPast
    @ObservationIgnored private let sleep = SleepManager()
    @ObservationIgnored private var tickCount = 0

    private init() {
        prefs = Prefs.load()
        if let d = UserDefaults.standard.data(forKey: "history"),
           let h = try? JSONDecoder().decode([HistoryPoint].self, from: d) { history = h }
    }

    func start() {
        applyAppearance()
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.tick() }
        if prefs.overlayOnLaunch { setOverlay(true) }
    }

    // MARK: Derived state

    var effectiveLimit: Int { prefs.topUp ? 100 : prefs.limit }
    var adapterMode: Bool { helper?.backend.hasPrefix("adapter") ?? false }
    var calibrationStage: Int? { helperRunning ? helper?.calibrationStage : nil }
    var displayPercent: Int { prefs.hardwarePercent ? Int(battery.rawPercent.rounded()) : battery.percent }

    enum ChargeState { case none, calibrating, discharging, charging, paused, heat, plugged, battery }
    var state: ChargeState {
        if !battery.present { return .none }
        if calibrationStage != nil { return .calibrating }
        if helperRunning, let h = helper {
            if h.heatBlocked && battery.externalConnected { return .heat }
            if h.discharging && !(adapterMode && battery.percent <= effectiveLimit) { return .discharging }
            if h.chargingInhibited && battery.externalConnected { return .paused }
        }
        if battery.isCharging { return .charging }
        return battery.externalConnected ? .plugged : .battery
    }
    var stateTitle: String {
        switch state {
        case .none: "未检测到电池"
        case .calibrating: "校准中 · 第 \(calibrationStage ?? 1)/5 步"
        case .discharging: "放电中"
        case .charging: "充电中"
        case .paused: adapterMode ? "已达限制 · 电池供电" : "已暂停充电"
        case .heat: "过热保护 · 已暂停"
        case .plugged: "已连接电源"
        case .battery: "使用电池"
        }
    }
    var stateColor: Color {
        switch state {
        case .charging: .green; case .discharging, .heat: .orange; case .paused, .calibrating: .blue
        case .plugged: .teal; default: .secondary
        }
    }
    var stateIcon: String {
        switch state {
        case .charging: "bolt.fill"; case .discharging: "arrow.down.circle.fill"; case .paused: "pause.circle.fill"
        case .heat: "flame.fill"; case .calibrating: "slider.vertical.3"; case .plugged: "powerplug.fill"
        case .battery: "battery.75percent"; case .none: "exclamationmark.triangle"
        }
    }

    // MARK: Tick

    func tick() {
        tickCount += 1
        battery = BatteryReader.read()
        helperInstalled = FileManager.default.fileExists(atPath: Paths.daemonPlist)
        helper = JSONFile.load(HelperStatus.self, Paths.status)
        helperRunning = helper.map { Date().timeIntervalSince($0.updated) < 15 } ?? false
        if prefs.topUp && battery.percent >= 100 { prefs.topUp = false }
        pushControl()
        recordHistory()
        updateSleep()
        runScheduler()
        if selection == .energy && tickCount % 2 == 0 { refreshProcesses() }
    }

    func refreshProcesses() { ProcessSampler.sample { [weak self] in self?.processes = $0 } }

    private func recordHistory() {
        guard battery.present else { return }
        if let last = history.last, Date().timeIntervalSince(last.date) < 120 { return }
        if !prefs.backgroundDashboard && !(NSApp.windows.contains { $0.isVisible && $0.identifier?.rawValue.contains("main") == true }) { return }
        history.append(HistoryPoint(date: Date(), percent: battery.percent, charging: battery.isCharging))
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        history.removeAll { $0.date < cutoff }
        if let d = try? JSONEncoder().encode(history) { UserDefaults.standard.set(d, forKey: "history") }
    }

    private func updateSleep() {
        let calibrating = calibrationStage != nil
        let discharging = helperRunning && helper?.discharging == true
        let toLimit = prefs.disableSleepUntilLimit && battery.externalConnected && battery.percent < effectiveLimit && state == .charging
        let sys = prefs.enabled && (calibrating || discharging || toLimit)
        sleep.update(system: sys, display: sys && prefs.displaySleep == .never)
    }

    // MARK: Control file

    func controlState(heartbeat: Date = Date()) -> ControlState {
        var c = ControlState()
        c.enabled = prefs.enabled; c.limit = prefs.limit; c.autoDischarge = prefs.autoDischarge
        c.sailing = prefs.sailing; c.sailingDiff = prefs.sailingDiff
        c.heatProtection = prefs.heatProtection; c.maxTemp = Double(prefs.maxTemp)
        c.topUp = prefs.topUp
        c.calibrationRequestID = prefs.calibrationRequestID; c.calibrationCancelID = prefs.calibrationCancelID
        c.appClosedStop = prefs.appClosedStop; c.stopOnSleep = prefs.stopOnSleep
        c.lowPowerMode = prefs.lowPowerMode.rawValue; c.ledMode = prefs.ledMode.rawValue
        c.ledIndicateLimit = prefs.ledIndicateLimit; c.ledBlinkDischarge = prefs.ledBlinkDischarge
        c.heartbeat = heartbeat
        return c
    }

    func pushControl(force: Bool = false, heartbeat: Date = Date()) {
        var c = controlState(heartbeat: heartbeat)
        var cmp = c; cmp.heartbeat = .distantPast
        var last = lastPushed; last?.heartbeat = .distantPast
        guard force || cmp != last || Date().timeIntervalSince(lastPush) > 10 else { return }
        try? FileManager.default.createDirectory(atPath: Paths.dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o777])
        if JSONFile.save(c, Paths.control) { lastPushed = c; lastPush = Date() }
        c.heartbeat = heartbeat
    }

    /// Called right before quitting so "stop charging when app closes" takes effect immediately.
    func willTerminate() { pushControl(force: true, heartbeat: .distantPast); sleep.update(system: false, display: false) }

    private func prefsChanged(from old: Prefs) {
        if old.showDock != prefs.showDock { applyDock() }
        if old.appearance != prefs.appearance { applyAppearance() }
        if old.overlayPercent != prefs.overlayPercent && overlayVisible { OverlayController.shared.show(edit: overlayEditing) }
        pushControl(force: true)
        updateSleep()
    }

    func applyDock() {
        NSApp.setActivationPolicy(prefs.showDock ? .regular : .accessory)
        if !prefs.showDock { DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) } }
    }

    func applyAppearance() {
        switch prefs.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // MARK: Actions

    func startCalibration() { prefs.calibrationRequestID += 1 }
    func stopCalibration() { prefs.calibrationCancelID += 1 }
    func pauseCharging() { prefs.topUp = false; prefs.limit = max(20, min(100, battery.percent)) }
    func startDischarge() { prefs.autoDischarge = true }

    func setOverlay(_ on: Bool, edit: Bool = false) {
        overlayVisible = on; overlayEditing = on && edit
        if on { OverlayController.shared.show(edit: edit) } else { OverlayController.shared.hide() }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { alert = "无法更改开机自启：\(error.localizedDescription)" }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func perform(_ action: TaskAction, value: Int = 80) {
        switch action {
        case .calibrate: startCalibration()
        case .topUp: prefs.topUp = true
        case .stopTopUp: prefs.topUp = false
        case .setLimit: prefs.limit = max(20, min(100, value))
        case .pause: pauseCharging()
        case .discharge: startDischarge()
        case .lowPowerOn: prefs.lowPowerMode = .always
        case .lowPowerOff: prefs.lowPowerMode = .never
        }
    }

    private func runScheduler() {
        let now = Date()
        for i in prefs.tasks.indices {
            let t = prefs.tasks[i]
            guard let due = t.nextDue, now >= due else { continue }
            let missed = now.timeIntervalSince(due) > 300
            if missed && !prefs.runMissedTasks {
                prefs.tasks[i].lastRun = now
                prefs.taskHistory.insert(TaskLog(date: now, name: t.name, action: t.action.title, skipped: true), at: 0)
            } else {
                perform(t.action, value: t.value)
                prefs.tasks[i].lastRun = now
                prefs.taskHistory.insert(TaskLog(date: now, name: t.name, action: t.action.title), at: 0)
            }
            if prefs.taskHistory.count > 100 { prefs.taskHistory.removeLast(prefs.taskHistory.count - 100) }
        }
    }

    func handle(url: URL) {
        guard url.scheme == "batterycare" else { return }
        let parts = ([url.host ?? ""] + url.pathComponents.filter { $0 != "/" }).map { $0.lowercased() }
        let arg = parts.dropFirst().first ?? URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "value" })?.value?.lowercased()
        switch parts.first {
        case "topup": perform(.topUp)
        case "pause": perform(.pause)
        case "discharge": perform(.discharge)
        case "calibrate": perform(.calibrate)
        case "limit": if let v = arg.flatMap(Int.init) { perform(.setLimit, value: v) }
        case "lowpower": perform(arg == "off" ? .lowPowerOff : .lowPowerOn)
        case "page":
            if let p = arg.flatMap(Page.init(rawValue:)) { selection = p; NSApp.activate(ignoringOtherApps: true) }
        case "enable": prefs.enabled = true
        case "disable": prefs.enabled = false
        default: break
        }
    }

    // MARK: Helper install

    private func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    @discardableResult
    private func runAdmin(_ cmd: String) -> Bool {
        let esc = cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var err: NSDictionary?
        NSAppleScript(source: "do shell script \"\(esc)\" with administrator privileges")?.executeAndReturnError(&err)
        if let err {
            if (err[NSAppleScript.errorNumber] as? Int) != -128 { alert = err[NSAppleScript.errorMessage] as? String ?? "操作失败" }
            return false
        }
        return true
    }

    func installHelper() {
        guard let res = Bundle.main.resourcePath, FileManager.default.fileExists(atPath: res + "/batterycare-helper") else {
            alert = "找不到辅助程序。请使用 build.sh 打包后的 .app 运行。"; return
        }
        pushControl(force: true)
        if runAdmin("/bin/bash \(q(res + "/install-helper.sh")) \(q(res + "/batterycare-helper"))") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.tick() }
        }
    }

    func uninstallHelper() {
        guard let res = Bundle.main.resourcePath else { return }
        if runAdmin("/bin/bash \(q(res + "/uninstall-helper.sh"))") { tick() }
    }

    func uninstallEverything() {
        let a = NSAlert()
        a.messageText = "删除电池管家？"
        a.informativeText = "将卸载后台辅助程序、恢复系统默认充电行为，并把应用移到废纸篓。"
        a.addButton(withTitle: "删除"); a.addButton(withTitle: "取消")
        a.buttons.first?.hasDestructiveAction = true
        guard a.runModal() == .alertFirstButtonReturn else { return }
        if helperInstalled { guard let res = Bundle.main.resourcePath, runAdmin("/bin/bash \(q(res + "/uninstall-helper.sh"))") else { return } }
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in NSApp.terminate(nil) }
    }

    func resetDefaults() {
        let a = NSAlert(); a.messageText = "恢复默认设置？"; a.informativeText = "所有设置、定时任务和历史记录都会被重置。"
        a.addButton(withTitle: "恢复"); a.addButton(withTitle: "取消")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        var p = Prefs()
        p.calibrationRequestID = prefs.calibrationRequestID; p.calibrationCancelID = prefs.calibrationCancelID
        prefs = p
    }

    func saveDebugFile() {
        struct Debug: Encodable { let date: Date; let battery: BatterySnapshot; let helper: HelperStatus?; let control: ControlState; let os: String }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "BatteryCare-debug.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let d = Debug(date: Date(), battery: battery, helper: helper, control: controlState(),
                      os: ProcessInfo.processInfo.operatingSystemVersionString)
        try? JSONFile.encode(d)?.write(to: url)
    }
}
