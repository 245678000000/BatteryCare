import SwiftUI
import Shared

enum Page: String, CaseIterable, Identifiable {
    case dashboard, charge, sleep, energy, schedule, shortcuts, overlay, menubar, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: "仪表板"; case .charge: "充电控制"; case .sleep: "睡眠行为"; case .energy: "能源使用"
        case .schedule: "定时设置"; case .shortcuts: "捷径"; case .overlay: "悬浮窗"; case .menubar: "菜单栏"; case .other: "其他"
        }
    }
    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2"; case .charge: "bolt.batteryblock.fill"; case .sleep: "moon.fill"
        case .energy: "leaf"; case .schedule: "calendar.badge.clock"; case .shortcuts: "square.stack.3d.up"
        case .overlay: "rectangle.inset.topright.filled"; case .menubar: "menubar.rectangle"; case .other: "shippingbox"
        }
    }
    static let sections: [(String?, [Page])] = [
        (nil, [.dashboard]),
        ("电池保养", [.charge, .sleep, .energy]),
        ("自动化", [.schedule, .shortcuts]),
        ("外观", [.overlay, .menubar, .other]),
    ]
}

enum DisplaySleep: String, Codable, CaseIterable { case mirror, never
    var title: String { self == .mirror ? "镜像 macOS" : "从不关闭" } }

enum LowPowerMode: String, Codable, CaseIterable { case macos, never, always, battery
    var title: String { switch self { case .macos: "跟随 macOS"; case .never: "始终关闭"; case .always: "始终开启"; case .battery: "仅使用电池时" } } }

enum LEDMode: String, Codable, CaseIterable { case system, on, off
    var title: String { switch self { case .system: "跟随系统"; case .on: "始终开启"; case .off: "始终关闭" } } }

enum Appearance: String, Codable, CaseIterable { case system, light, dark
    var title: String { switch self { case .system: "系统"; case .light: "浅色"; case .dark: "深色" } } }

enum IconStyle: String, Codable, CaseIterable { case hidden, app, status, macos
    var title: String { switch self { case .hidden: "不要显示"; case .app: "应用图标"; case .status: "状态图标"; case .macos: "macOS 电池" } }
    var icon: String { switch self { case .hidden: "eye.slash"; case .app: "leaf.circle"; case .status: "bolt.batteryblock"; case .macos: "battery.75percent" } } }

enum HighPowerThreshold: Int, Codable, CaseIterable { case low = 20, medium = 50, high = 90
    var title: String { switch self { case .low: "轻度使用（>20% CPU）"; case .medium: "中等使用（>50% CPU）"; case .high: "高负载（>90% CPU）" } } }

enum MenuItemKind: String, Codable, CaseIterable, Identifiable {
    case maxCapacity, health, cycles, temperature, timeRemaining, current, voltage, power
    case adapterCurrent, adapterVoltage, adapterPower, calibration, heat, sailing, topUp
    var id: String { rawValue }
    var title: String {
        switch self {
        case .maxCapacity: "最大容量"; case .health: "健康度"; case .cycles: "循环"; case .temperature: "温度"
        case .timeRemaining: "剩余时间"; case .current: "电流"; case .voltage: "电压"; case .power: "功率"
        case .adapterCurrent: "电流"; case .adapterVoltage: "电压"; case .adapterPower: "功率"
        case .calibration: "校准模式"; case .heat: "过热保护"; case .sailing: "航海模式"; case .topUp: "充满"
        }
    }
    var icon: String {
        switch self {
        case .maxCapacity: "heart.text.square"; case .health: "stethoscope"; case .cycles: "arrow.triangle.2.circlepath"
        case .temperature: "thermometer.medium"; case .timeRemaining: "clock"; case .current: "minus.plus.batteryblock"
        case .voltage: "bolt"; case .power: "gauge.with.dots.needle.33percent"
        case .adapterCurrent, .adapterVoltage, .adapterPower: "powerplug"
        case .calibration: "slider.vertical.3"; case .heat: "flame"; case .sailing: "paperplane.fill"; case .topUp: "plus.circle"
        }
    }
    static let groups: [(String, [MenuItemKind])] = [
        ("电池健康", [.maxCapacity, .health, .cycles]),
        ("电池规格", [.temperature, .timeRemaining, .current, .voltage, .power]),
        ("电源适配器规格", [.adapterCurrent, .adapterVoltage, .adapterPower]),
        ("状态", [.calibration, .heat, .sailing, .topUp]),
    ]
}

enum TaskAction: String, Codable, CaseIterable {
    case calibrate, topUp, stopTopUp, setLimit, pause, discharge, lowPowerOn, lowPowerOff
    var title: String {
        switch self {
        case .calibrate: "启动校准模式"; case .topUp: "充满至 100%"; case .stopTopUp: "结束充满"
        case .setLimit: "设置充电限制"; case .pause: "暂停充电"; case .discharge: "开始放电"
        case .lowPowerOn: "开启低电量模式"; case .lowPowerOff: "关闭低电量模式"
        }
    }
}

enum RepeatRule: String, Codable, CaseIterable {
    case once, daily, weekly, monthly
    var title: String { switch self { case .once: "仅一次"; case .daily: "每天"; case .weekly: "每周"; case .monthly: "每月" } }
    var component: Calendar.Component? { switch self { case .once: nil; case .daily: .day; case .weekly: .weekOfYear; case .monthly: .month } }
}

struct ScheduledTask: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = "新任务"
    var action: TaskAction = .calibrate
    var value = 80
    var rule: RepeatRule = .once
    var start = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
    var enabled = true
    var lastRun: Date?

    /// Next fire time that is later than lastRun (or start if never run).
    var nextDue: Date? {
        guard enabled else { return nil }
        guard let last = lastRun else { return start }
        guard let comp = rule.component else { return nil }
        var d = start, n = 0
        while d <= last && n < 5000 { n += 1; d = Calendar.current.date(byAdding: comp, value: n, to: start)! }
        return d > last ? d : nil
    }
}

struct TaskLog: Codable, Equatable, Identifiable {
    var id = UUID()
    var date: Date
    var name: String
    var action: String
    var skipped = false
}

struct HistoryPoint: Codable, Equatable, Identifiable {
    var date: Date
    var percent: Int
    var charging: Bool
    var id: Date { date }
}

struct ProcInfo: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var cpu: Double
    var icon: NSImage?
}

struct Prefs: Codable, Equatable {
    // charge
    var enabled = true
    var limit = 80
    var autoDischarge = false
    var sailing = true
    var sailingDiff = 5
    var heatProtection = true
    var maxTemp = 35
    var topUp = false
    var calibrationRequestID = 0
    var calibrationCancelID = 0
    // sleep
    var disableSleepUntilLimit = false
    var displaySleep: DisplaySleep = .mirror
    var stopOnSleep = false
    var appClosedStop = false
    // energy
    var lowPowerMode: LowPowerMode = .macos
    var backgroundDashboard = true
    var highPower: HighPowerThreshold = .medium
    // schedule
    var tasks: [ScheduledTask] = []
    var runMissedTasks = false
    var taskHistory: [TaskLog] = []
    // overlay
    var overlayOnLaunch = false
    var overlayPercent = true
    var overlayX: Double?
    var overlayY: Double?
    // menu bar
    var iconStyle: IconStyle = .app
    var iconPercent = true
    var lowPowerColor = false
    var menuItems: [MenuItemKind] = []
    // other
    var hardwarePercent = false
    var showDock = true
    var reduceTransparency = false
    var appearance: Appearance = .system
    var ledMode: LEDMode = .system
    var ledIndicateLimit = false
    var ledBlinkDischarge = false

    static let key = "prefs.v1"
    static func load() -> Prefs {
        guard let d = UserDefaults.standard.data(forKey: key) else { return Prefs() }
        if let p = try? JSONDecoder().decode(Prefs.self, from: d) { return p }
        // Merge saved values over defaults (handles fields added in newer versions).
        guard let saved = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let defData = try? JSONEncoder().encode(Prefs()),
              var merged = try? JSONSerialization.jsonObject(with: defData) as? [String: Any] else { return Prefs() }
        for (k, v) in saved where merged[k] != nil {
            var trial = merged; trial[k] = v
            if let td = try? JSONSerialization.data(withJSONObject: trial), (try? JSONDecoder().decode(Prefs.self, from: td)) != nil { merged = trial }
        }
        guard let md = try? JSONSerialization.data(withJSONObject: merged), let p = try? JSONDecoder().decode(Prefs.self, from: md) else { return Prefs() }
        return p
    }
    func save() { if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Prefs.key) } }
}
