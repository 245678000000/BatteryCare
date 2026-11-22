import Foundation
import IOKit
import IOKit.pwr_mgt
import Shared

setvbuf(stdout, nil, _IOLBF, 0)

func log(_ s: String) {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    print("[\(f.string(from: Date()))] \(s)")
}

// MARK: - CLI mode (for Shortcuts "Run Shell Script")

let args = Array(CommandLine.arguments.dropFirst())
if let cmd = args.first {
    let b = BatteryReader.read()
    let c = JSONFile.load(ControlState.self, Paths.control)
    let st = JSONFile.load(HelperStatus.self, Paths.status)
    switch (cmd, args.dropFirst().first) {
    case ("get", "percent"?): print(b.percent)
    case ("get", "limit"?): print(c.map { $0.topUp ? 100 : $0.limit } ?? 100)
    case ("get", "temperature"?): print(b.temperature.map { String(format: "%.1f", $0) } ?? "")
    case ("get", "state"?):
        if st?.calibrationStage != nil { print("calibrating") }
        else if st?.discharging == true { print("discharging") }
        else if b.isCharging { print("charging") }
        else if b.externalConnected && st?.chargingInhibited == true { print("paused") }
        else { print(b.externalConnected ? "plugged" : "battery") }
    case ("probe", _):
        for k in ["CHTE", "CH0B", "CH0C", "CHIE", "CH0I", "ACLC", "TB0T"] {
            print(k, SMC.read(k).map { "\($0.type) \($0.bytes)" } ?? "-")
        }
    case ("keys", let prefix):
        for k in SMC.allKeys() where k.hasPrefix(prefix ?? "") {
            print(k, SMC.read(k).map { "\($0.type) \($0.bytes)" } ?? "-")
        }
    case ("status", _):
        if let d = JSONFile.encode(b) { print(String(decoding: d, as: UTF8.self)) }
    default:
        print("usage: batterycare-helper get percent|limit|state|temperature  |  status")
        exit(1)
    }
    exit(0)
}

// MARK: - Charge backend (SMC keys differ across firmware generations)

struct Backend {
    var name = "none"
    var inhibitKeys: [(key: String, on: [UInt8], off: [UInt8])] = []
    var dischargeKey: (key: String, on: [UInt8], off: [UInt8])?
    var hasLED = false
    /// macOS 27-era firmware: charge-inhibit keys are gated, so the limit is held by cutting wall power (CHIE).
    var adapterMode: Bool { inhibitKeys.isEmpty && dischargeKey != nil }
    var canControl: Bool { !inhibitKeys.isEmpty || dischargeKey != nil }

    static func detect() -> Backend {
        var b = Backend()
        func sized(_ key: String, _ first: UInt8) -> [UInt8]? {
            guard let r = SMC.read(key), !r.bytes.isEmpty else { return nil }  // zero-size = gated placeholder
            var a = [UInt8](repeating: 0, count: r.bytes.count); if !a.isEmpty { a[0] = first }; return a
        }
        if let on = sized("CHTE", 1) {
            b.name = "CHTE"; b.inhibitKeys = [("CHTE", on, [UInt8](repeating: 0, count: on.count))]
        } else if let on = sized("CH0B", 2), let on2 = sized("CH0C", 2) {
            b.name = "CH0B/CH0C"
            b.inhibitKeys = [("CH0B", on, [UInt8](repeating: 0, count: on.count)),
                             ("CH0C", on2, [UInt8](repeating: 0, count: on2.count))]
        }
        if let on = sized("CHIE", 8) { b.dischargeKey = ("CHIE", on, [UInt8](repeating: 0, count: on.count)) }
        else if let on = sized("CH0I", 1) { b.dischargeKey = ("CH0I", on, [UInt8](repeating: 0, count: on.count)) }
        b.hasLED = SMC.exists("ACLC")
        if b.adapterMode { b.name = "adapter (\(b.dischargeKey!.key))" }
        return b
    }

    func setInhibit(_ v: Bool) -> Bool {
        if adapterMode { return setDischarge(v) }
        return inhibitKeys.allSatisfy { SMC.write($0.key, v ? $0.on : $0.off) }
    }
    func setDischarge(_ v: Bool) -> Bool { dischargeKey.map { SMC.write($0.key, v ? $0.on : $0.off) } ?? false }
    func setLED(_ v: UInt8) { if hasLED { SMC.write("ACLC", [v]) } }
}

func pmset(_ a: [String]) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); p.arguments = a
    try? p.run(); p.waitUntilExit()
}

// MARK: - Engine

final class Engine {
    let backend: Backend
    var status: HelperStatus
    var control: ControlState?
    var inhibited: Bool?
    var discharging: Bool?
    var led: UInt8?
    var lowPower: String?
    var sleepDisabled: Bool?
    var blink = false
    var heatLatched = false
    var ticks = 0

    init() {
        _ = SMC.open()
        backend = Backend.detect()
        status = JSONFile.load(HelperStatus.self, Paths.status) ?? HelperStatus()
        status.backend = backend.name
        status.smcAvailable = backend.canControl
        log("helper started, backend=\(backend.name) discharge=\(backend.dischargeKey?.key ?? "-") led=\(backend.hasLED)")
    }

    func setStage(_ s: Int?) {
        status.calibrationStage = s
        status.calibrationStageStart = s == nil ? nil : Date()
        log("calibration stage -> \(s.map(String.init) ?? "done/none")")
    }

    func tick() {
        ticks += 1
        guard let c = JSONFile.load(ControlState.self, Paths.control) else { restore(); write(); return }
        control = c
        let b = BatteryReader.read()
        guard b.present else { write(); return }
        let p = b.percent

        // First run: adopt request counters so old requests don't fire.
        if status.handledCalibrationID == nil { status.handledCalibrationID = c.calibrationRequestID }
        if status.handledCancelID == nil { status.handledCancelID = c.calibrationCancelID }
        if c.calibrationRequestID != status.handledCalibrationID {
            status.handledCalibrationID = c.calibrationRequestID; setStage(1)
        }
        if c.calibrationCancelID != status.handledCancelID {
            status.handledCancelID = c.calibrationCancelID; if status.calibrationStage != nil { setStage(nil) }
        }

        var wantInhibit = false, wantDischarge = false
        status.heatBlocked = false
        if !b.externalConnected { heatLatched = false }

        if !c.enabled {
            // everything released
        } else if let stage = status.calibrationStage {
            switch stage {
            case 1: if p >= 100 || b.fullyCharged { setStage(2) }
            case 2: wantInhibit = true; wantDischarge = b.externalConnected; if p <= 10 { setStage(3) }
            case 3: if p >= 100 || b.fullyCharged { setStage(4) }
            case 4:
                wantInhibit = true
                if Date().timeIntervalSince(status.calibrationStageStart ?? Date()) > 3600 { setStage(5) }
            default:
                wantInhibit = true; wantDischarge = b.externalConnected && p > c.limit
                if p <= c.limit { status.lastCalibration = Date(); setStage(nil) }
            }
            // re-evaluate the new stage on the same tick
            if let s = status.calibrationStage {
                wantInhibit = [2, 4, 5].contains(s)
                wantDischarge = (s == 2 && b.externalConnected) || (s == 5 && b.externalConnected && p > c.limit)
            } else { wantInhibit = p >= c.limit; wantDischarge = false }
        } else if c.appClosedStop && Date().timeIntervalSince(c.heartbeat) > 40 {
            wantInhibit = true
        } else {
            let limit = c.topUp ? 100 : c.limit
            if limit < 100 {
                if p >= limit { wantInhibit = true }
                else {
                    // hysteresis; adapter mode always needs a small band or it would flap at the limit
                    let diff = c.sailing ? c.sailingDiff : (backend.adapterMode ? 3 : 0)
                    if (inhibited ?? false) && p > limit - diff { wantInhibit = true }
                }
            }
            if c.autoDischarge && b.externalConnected && p > limit { wantDischarge = true }
            // Heat protection only matters while plugged in; release 1 °C below the limit (hysteresis).
            if c.heatProtection, b.externalConnected, let t = b.temperature, !wantInhibit,
               t >= c.maxTemp || (heatLatched && t > c.maxTemp - 1) {
                wantInhibit = true; status.heatBlocked = true
            }
            heatLatched = status.heatBlocked
        }

        let refresh = ticks % 20 == 0  // re-assert periodically (firmware may reset after wake)
        if backend.adapterMode {
            let cut = wantInhibit || wantDischarge
            if cut != inhibited || refresh {
                if backend.setDischarge(cut) {
                    if cut != inhibited { log("adapter \(cut ? "cut" : "restored") at \(p)%") }
                    inhibited = cut; discharging = cut && b.externalConnected; status.message = nil
                } else { status.message = "写入 SMC 失败（CHIE）" }
            }
        } else if status.smcAvailable && (wantInhibit != inhibited || refresh) {
            if backend.setInhibit(wantInhibit) {
                if wantInhibit != inhibited { log("charging \(wantInhibit ? "inhibited" : "allowed") at \(p)%") }
                inhibited = wantInhibit; status.message = nil
            } else { status.message = "写入 SMC 失败（充电控制）" }
        }
        if !backend.adapterMode && backend.dischargeKey != nil && (wantDischarge != discharging || refresh) {
            if backend.setDischarge(wantDischarge) {
                if wantDischarge != discharging { log("discharge \(wantDischarge ? "on" : "off") at \(p)%") }
                discharging = wantDischarge
            }
        }
        status.chargingInhibited = inhibited ?? false
        status.discharging = discharging ?? false

        // Keep the Mac awake while discharging on adapter / calibrating (lid-closed too).
        let noSleep = c.enabled && (wantDischarge || status.calibrationStage != nil)
        if noSleep != sleepDisabled { pmset(["-a", "disablesleep", noSleep ? "1" : "0"]); sleepDisabled = noSleep }

        // Low power mode
        if c.lowPowerMode != lowPower {
            switch c.lowPowerMode {
            case "never": pmset(["-a", "lowpowermode", "0"])
            case "always": pmset(["-a", "lowpowermode", "1"])
            case "battery": pmset(["-b", "lowpowermode", "1"]); pmset(["-c", "lowpowermode", "0"])
            default: break
            }
            lowPower = c.lowPowerMode
        }

        // MagSafe LED: 0 system, 1 off, 3 green, 4 orange
        var wantLED: UInt8 = 0
        blink.toggle()
        switch c.ledMode {
        case "off": wantLED = 1
        case "on": wantLED = b.isCharging ? 4 : 3
        default: wantLED = 0
        }
        if c.ledMode != "off" {
            if c.ledIndicateLimit && (inhibited ?? false) && b.externalConnected { wantLED = 3 }
            if c.ledBlinkDischarge && (discharging ?? false) { wantLED = blink ? 4 : 1 }
        }
        if wantLED != led { backend.setLED(wantLED); led = wantLED }

        write()
    }

    func onSleep() {
        if backend.adapterMode {
            // never leave wall power cut while asleep
            if inhibited == true { _ = backend.setDischarge(false); log("sleep: adapter restored") }
            inhibited = nil; discharging = nil; return
        }
        guard let c = control, c.enabled, c.stopOnSleep, status.smcAvailable else { return }
        if backend.setInhibit(true) { inhibited = true; log("sleep: charging inhibited") }
    }

    func restore() {
        if inhibited != false, status.smcAvailable, !backend.adapterMode { _ = backend.setInhibit(false); inhibited = false }
        if (discharging != false || backend.adapterMode), backend.dischargeKey != nil { _ = backend.setDischarge(false); discharging = false }
        if led != 0 { backend.setLED(0); led = 0 }
        if sleepDisabled == true { pmset(["-a", "disablesleep", "0"]); sleepDisabled = false }
        status.chargingInhibited = false; status.discharging = false
    }

    func write() {
        status.updated = Date()
        try? FileManager.default.createDirectory(atPath: Paths.dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o777])
        JSONFile.save(status, Paths.status)
    }
}

let engine = Engine()

// MARK: - Sleep notifications

var rootPort: io_connect_t = 0
var notifier: io_object_t = 0
var notifyPort: IONotificationPortRef?
rootPort = IORegisterForSystemPower(nil, &notifyPort, { _, _, type, arg in
    let msg = Int(type)
    if msg == Int(bitPattern: UInt(0xE0000280)) || msg == Int(bitPattern: UInt(0xE0000270)) {
        // kIOMessageSystemWillSleep / kIOMessageCanSystemSleep
        if msg == Int(bitPattern: UInt(0xE0000280)) { engine.onSleep() }
        IOAllowPowerChange(rootPort, Int(bitPattern: arg))
    } else if msg == Int(bitPattern: UInt(0xE0000300)) { // kIOMessageSystemHasPoweredOn
        engine.inhibited = nil; engine.discharging = nil; engine.tick()
    }
}, &notifier)
if let port = notifyPort {
    CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .commonModes)
}

// MARK: - Signals & loop

signal(SIGTERM, SIG_IGN); signal(SIGINT, SIG_IGN)
var sources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT] {
    let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    s.setEventHandler { log("stopping, restoring defaults"); engine.restore(); engine.write(); exit(0) }
    s.resume(); sources.append(s)
}

let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now(), repeating: 3)
timer.setEventHandler { engine.tick() }
timer.resume()

RunLoop.main.run()
