import Foundation
import IOKit
import IOKit.ps
import CSMC

// MARK: - Paths shared by the app and the root helper

public enum Paths {
    public static let dir = "/Users/Shared/BatteryCare"
    public static let control = dir + "/control.json"
    public static let status = dir + "/status.json"
    public static let log = dir + "/helper.log"
    public static let label = "com.batterycare.helper"
    public static let helperBinary = "/Library/PrivilegedHelperTools/com.batterycare.helper"
    public static let daemonPlist = "/Library/LaunchDaemons/com.batterycare.helper.plist"
}

/// Written by the app, read by the helper.
public struct ControlState: Codable, Equatable {
    public var enabled = true
    public var limit = 80
    public var autoDischarge = false
    public var sailing = false
    public var sailingDiff = 5
    public var heatProtection = false
    public var maxTemp = 35.0
    public var topUp = false
    public var calibrationRequestID = 0
    public var calibrationCancelID = 0
    public var appClosedStop = false
    public var stopOnSleep = false
    public var lowPowerMode = "macos"   // macos | never | always | battery
    public var ledMode = "system"       // system | off | on
    public var ledIndicateLimit = false
    public var ledBlinkDischarge = false
    public var heartbeat = Date()
    public init() {}
}

/// Written by the helper, read by the app.
public struct HelperStatus: Codable, Equatable {
    public var updated = Date()
    public var backend = "unknown"
    public var smcAvailable = false
    public var chargingInhibited = false
    public var discharging = false
    public var heatBlocked = false
    public var calibrationStage: Int? = nil
    public var calibrationStageStart: Date? = nil
    public var lastCalibration: Date? = nil
    public var handledCalibrationID: Int? = nil
    public var handledCancelID: Int? = nil
    public var message: String? = nil
    public init() {}
}

public enum JSONFile {
    static let enc: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }()
    static let dec: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d
    }()
    public static func load<T: Decodable>(_ t: T.Type, _ path: String) -> T? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? dec.decode(T.self, from: data)
    }
    @discardableResult
    public static func save<T: Encodable>(_ v: T, _ path: String) -> Bool {
        guard let data = try? enc.encode(v) else { return false }
        do { try data.write(to: URL(fileURLWithPath: path), options: .atomic); return true } catch { return false }
    }
    public static func encode<T: Encodable>(_ v: T) -> Data? { try? enc.encode(v) }
}

// MARK: - SMC

public enum SMC {
    public static func open() -> Bool { smc_open() == 0 }

    public static func read(_ key: String) -> (bytes: [UInt8], type: String)? {
        var buf = [UInt8](repeating: 0, count: 32)
        var size: UInt32 = 0
        var type = [CChar](repeating: 0, count: 5)
        let r = key.withCString { smc_read_key($0, &buf, &size, &type) }
        guard r == 0 else { return nil }
        let t = String(decoding: type.prefix(4).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return (Array(buf.prefix(Int(size))), t)
    }

    public static func allKeys() -> [String] {
        let n = smc_key_count(); guard n > 0 else { return [] }
        var out: [String] = []
        for i in 0..<UInt32(n) {
            var b = [CChar](repeating: 0, count: 5)
            if smc_key_at(i, &b) == 0 { out.append(String(decoding: b.prefix(4).map { UInt8(bitPattern: $0) }, as: UTF8.self)) }
        }
        return out
    }

    public static func exists(_ key: String) -> Bool { read(key) != nil }

    @discardableResult
    public static func write(_ key: String, _ bytes: [UInt8]) -> Bool {
        key.withCString { k in bytes.withUnsafeBufferPointer { smc_write_key(k, $0.baseAddress, UInt32(bytes.count)) } } == 0
    }

    public static func double(_ key: String) -> Double? {
        guard let (b, t) = read(key), !b.isEmpty else { return nil }
        switch t {
        case "flt " where b.count >= 4:
            return Double(Float(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24))
        case "sp78" where b.count >= 2:
            return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256.0
        case "ui8 ": return Double(b[0])
        case "ui16" where b.count >= 2: return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
        default: return nil
        }
    }

    public static func batteryTemperature() -> Double? {
        for k in ["TB0T", "TB1T", "TB2T", "TB0t"] {
            if let v = double(k), v > 5, v < 100 { return v }
        }
        return nil
    }
}

// MARK: - Battery

public struct BatterySnapshot: Codable, Equatable {
    public var present = false
    public var percent = 0
    public var rawPercent: Double = 0
    public var isCharging = false
    public var externalConnected = false
    public var fullyCharged = false
    public var cycleCount = 0
    public var designCycleCount = 1000
    public var designCapacity = 0      // mAh
    public var maxCapacity = 0         // mAh (raw full charge)
    public var currentCapacity = 0     // mAh
    public var voltage: Double = 0     // V
    public var amperage: Double = 0    // A (negative = discharging)
    public var temperature: Double?    // °C
    public var minutesRemaining: Int?
    public var adapterWatts: Int?
    public var adapterName: String?
    public var adapterVoltage: Double? // V
    public var adapterCurrent: Double? // A
    public init() {}

    public var health: Double { designCapacity > 0 ? min(Double(maxCapacity) / Double(designCapacity) * 100, 100) : 0 }
    public var power: Double { voltage * amperage }
}

public enum BatteryReader {
    public static func read() -> BatterySnapshot {
        var s = BatterySnapshot()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return s }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return s }
        let data = dict["BatteryData"] as? [String: Any] ?? [:]
        func num(_ k: String) -> Int64? {
            (dict[k] as? NSNumber)?.int64Value ?? (data[k] as? NSNumber)?.int64Value
        }
        func bool(_ k: String) -> Bool { (dict[k] as? Bool) ?? ((dict[k] as? NSNumber)?.boolValue ?? false) }

        s.present = bool("BatteryInstalled") || num("CurrentCapacity") != nil
        s.percent = Int(num("CurrentCapacity") ?? 0)
        s.isCharging = bool("IsCharging")
        s.externalConnected = bool("ExternalConnected")
        s.fullyCharged = bool("FullyCharged")
        s.cycleCount = Int(num("CycleCount") ?? 0)
        if let d = num("DesignCycleCount9C"), d > 0 { s.designCycleCount = Int(d) }
        s.designCapacity = Int(num("DesignCapacity") ?? 0)
        s.maxCapacity = Int(num("AppleRawMaxCapacity") ?? num("NominalChargeCapacity") ?? 0)
        s.currentCapacity = Int(num("AppleRawCurrentCapacity") ?? 0)
        s.rawPercent = s.maxCapacity > 0 ? Double(s.currentCapacity) / Double(s.maxCapacity) * 100 : Double(s.percent)
        s.voltage = Double(num("Voltage") ?? 0) / 1000
        s.amperage = Double(num("Amperage") ?? num("InstantAmperage") ?? 0) / 1000

        if let t = num("Temperature"), t > 0 { s.temperature = Double(t) / 100 }
        else if let t = num("VirtualTemperature"), t > 0 { s.temperature = Double(t) / 100 }
        else { s.temperature = SMC.batteryTemperature() }

        let remain: Int64? = s.isCharging ? (data["AvgTimeToFull"] as? NSNumber)?.int64Value ?? num("AvgTimeToFull")
                                          : num("TimeRemaining") ?? num("AvgTimeToEmpty")
        if let r = remain, r > 0, r < 65535 { s.minutesRemaining = Int(r) }

        if s.externalConnected, let ad = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            s.adapterWatts = (ad["Watts"] as? NSNumber)?.intValue
            s.adapterName = ad["Name"] as? String
            if let v = (ad["AdapterVoltage"] as? NSNumber)?.doubleValue { s.adapterVoltage = v / 1000 }
            if let c = (ad["Current"] as? NSNumber)?.doubleValue { s.adapterCurrent = c / 1000 }
        }
        return s
    }
}
