import AppKit
import SwiftUI
import IOKit.pwr_mgt

/// Holds IOPM assertions to keep the Mac (and optionally the display) awake.
final class SleepManager {
    private var sysID: IOPMAssertionID = 0
    private var dispID: IOPMAssertionID = 0

    func update(system: Bool, display: Bool) {
        set(&sysID, on: system, type: "PreventUserIdleSystemSleep")
        set(&dispID, on: display, type: "PreventUserIdleDisplaySleep")
    }

    private func set(_ id: inout IOPMAssertionID, on: Bool, type: String) {
        if on && id == 0 {
            IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "电池管家：充电/校准进行中" as CFString, &id)
        } else if !on && id != 0 {
            IOPMAssertionRelease(id); id = 0
        }
    }
}

/// A small floating HUD panel that shows the battery state above all windows.
final class OverlayController {
    static let shared = OverlayController()
    private var panel: NSPanel?
    private var moveObserver: Any?

    func show(edit: Bool) {
        let model = AppModel.shared
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 70),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.contentView = NSHostingView(rootView: OverlayHUD().environment(model))
            if let x = model.prefs.overlayX, let y = model.prefs.overlayY {
                p.setFrameOrigin(NSPoint(x: x, y: y))
            } else if let s = NSScreen.main?.visibleFrame {
                p.setFrameOrigin(NSPoint(x: s.maxX - 260, y: s.maxY - 90))
            }
            moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak p] _ in
                guard let o = p?.frame.origin else { return }
                AppModel.shared.prefs.overlayX = o.x; AppModel.shared.prefs.overlayY = o.y
            }
            panel = p
        }
        panel?.ignoresMouseEvents = !edit
        panel?.isMovableByWindowBackground = edit
        panel?.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }
}

enum ProcessSampler {
    static func sample(completion: @escaping ([ProcInfo]) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let p = Process(); let pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: "/bin/ps")
            p.arguments = ["-Aceo", "pcpu=,comm="]
            p.standardOutput = pipe
            guard (try? p.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            var agg: [String: Double] = [:]
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard let sp = t.firstIndex(of: " "), let cpu = Double(t[..<sp]) else { continue }
                agg[String(t[sp...]).trimmingCharacters(in: .whitespaces), default: 0] += cpu
            }
            let top = agg.sorted { $0.value > $1.value }.prefix(12)
            DispatchQueue.main.async {
                let apps = NSWorkspace.shared.runningApplications
                completion(top.map { name, cpu in
                    let app = apps.first { $0.executableURL?.lastPathComponent == name }
                    return ProcInfo(name: app?.localizedName ?? name, cpu: cpu, icon: app?.icon)
                })
            }
        }
    }
}
