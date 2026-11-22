import SwiftUI
import Shared

extension AppModel {
    func menuText(_ k: MenuItemKind) -> String? {
        let b = battery
        switch k {
        case .maxCapacity: return "\(b.maxCapacity)mAh"
        case .health: return String(format: "%.0f%%♥", b.health)
        case .cycles: return "\(b.cycleCount)次"
        case .temperature: return b.temperature.map { String(format: "%.1f°", $0) }
        case .timeRemaining: return b.minutesRemaining.map { String(format: "%d:%02d", $0 / 60, $0 % 60) }
        case .current: return String(format: "%.2fA", b.amperage)
        case .voltage: return String(format: "%.2fV", b.voltage)
        case .power: return String(format: "%.1fW", b.power)
        case .adapterCurrent: return b.adapterCurrent.map { String(format: "%.1fA", $0) }
        case .adapterVoltage: return b.adapterVoltage.map { String(format: "%.0fV", $0) }
        case .adapterPower: return b.adapterWatts.map { "\($0)W" }
        case .calibration: return calibrationStage != nil ? "校准" : nil
        case .heat: return helper?.heatBlocked == true ? "过热" : nil
        case .sailing: return prefs.sailing ? "航海" : nil
        case .topUp: return prefs.topUp ? "充满" : nil
        }
    }

    var menuBarText: String {
        var parts: [String] = []
        if prefs.iconPercent { parts.append("\(displayPercent)%") }
        parts += prefs.menuItems.compactMap { menuText($0) }
        return parts.joined(separator: " ")
    }

    var menuBarSymbol: String {
        switch prefs.iconStyle {
        case .hidden: return "leaf.circle"
        case .app: return "leaf.circle"
        case .status:
            switch state {
            case .charging: return "bolt.circle"; case .paused: return "pause.circle"; case .discharging: return "arrow.down.circle"
            case .heat: return "flame"; case .calibrating: return "slider.vertical.3"; default: return "leaf.circle"
            }
        case .macos:
            let p = battery.percent
            let level = p > 87 ? "100" : p > 62 ? "75" : p > 37 ? "50" : p > 12 ? "25" : "0"
            return battery.isCharging ? "battery.100percent.bolt" : "battery.\(level)percent"
        }
    }

    var menuBarImage: NSImage {
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let lowPower = prefs.lowPowerColor && ProcessInfo.processInfo.isLowPowerModeEnabled
        let img = NSImage(systemSymbolName: menuBarSymbol, accessibilityDescription: "电池管家")?
            .withSymbolConfiguration(lowPower ? cfg.applying(.init(paletteColors: [.systemYellow])) : cfg) ?? NSImage()
        img.isTemplate = !lowPower
        return img
    }
}

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: model.menuBarImage)
            if !model.menuBarText.isEmpty { Text(model.menuBarText) }
        }
    }
}

struct MenuBarSettingsView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var m = model
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(icon: "menubar.rectangle", title: "菜单栏预览", help: "这就是菜单栏里显示的样子。选中的信息项会依次显示在图标后面。")
            Card(padding: 20) {
                HStack(spacing: 5) {
                    if model.prefs.iconStyle == .hidden { Text("（不显示）").foregroundStyle(.secondary) }
                    else {
                        Image(nsImage: model.menuBarImage)
                        if !model.menuBarText.isEmpty { Text(model.menuBarText).font(.system(size: 13.5, weight: .medium)) }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
            }
            SectionHeader(icon: "book", title: "菜单项目录").padding(.top, 10)
            Card {
                VStack(alignment: .leading, spacing: 18) {
                    group("主图标样式", note: "（选择一个）") {
                        ForEach(IconStyle.allCases, id: \.self) { s in
                            Chip(icon: s.icon, title: s.title, selected: m.prefs.iconStyle == s) {
                                m.prefs.iconStyle = s
                                if s == .hidden { m.prefs.showDock = true }
                            }
                        }
                    }
                    group("主图标选项") {
                        Chip(icon: "percent", title: "显示百分比", selected: m.prefs.iconPercent) { m.prefs.iconPercent.toggle() }
                        Chip(icon: "paintpalette", title: "低电量模式颜色", selected: m.prefs.lowPowerColor) { m.prefs.lowPowerColor.toggle() }
                    }
                    ForEach(MenuItemKind.groups, id: \.0) { g in
                        group(g.0) {
                            ForEach(g.1) { k in
                                Chip(icon: k.icon, title: k.title, selected: m.prefs.menuItems.contains(k)) {
                                    if let i = m.prefs.menuItems.firstIndex(of: k) { m.prefs.menuItems.remove(at: i) } else { m.prefs.menuItems.append(k) }
                                }
                            }
                        }
                    }
                    Divider()
                    HStack {
                        Spacer()
                        Button { m.prefs.iconStyle = .app; m.prefs.iconPercent = true; m.prefs.lowPowerColor = false; m.prefs.menuItems = [] } label: {
                            Label("重置", systemImage: "arrow.clockwise")
                        }.buttonStyle(SoftButtonStyle())
                        Button { m.prefs.menuItems = []; m.prefs.iconPercent = false } label: { Label("全部清除", systemImage: "trash") }
                            .buttonStyle(SoftButtonStyle(destructive: true))
                    }
                }
            }
        }
    }

    private func group<C: View>(_ title: String, note: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 15, weight: .semibold))
                if let note { Text(note).font(.system(size: 12.5)).foregroundStyle(.secondary) }
            }
            FlowLayout(spacing: 10) { content() }
        }
    }
}

/// The popover that opens from the menu bar icon.
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        @Bindable var m = model
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                BatteryGlyph(percent: model.displayPercent, limit: model.effectiveLimit,
                             color: model.stateColor == .secondary ? .green : model.stateColor)
                    .frame(width: 62, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.displayPercent)%").font(.system(size: 24, weight: .bold, design: .rounded))
                    Label(model.stateTitle, systemImage: model.stateIcon).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(model.stateColor == .secondary ? Color.secondary : model.stateColor)
                }
                Spacer()
                Button { m.prefs.enabled.toggle() } label: { Image(systemName: "power") }
                    .buttonStyle(.plain).font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(model.prefs.enabled ? .green : .secondary).help("暂停/恢复电池管理")
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text("充电限制").font(.system(size: 12.5, weight: .medium)); Spacer(); Text("\(m.prefs.limit)%").font(.system(size: 12.5, weight: .bold).monospacedDigit()) }
                Slider(value: Binding(get: { Double(m.prefs.limit) }, set: { m.prefs.limit = Int($0.rounded()) }), in: 20...100, step: 5)
                    .tint(Color.accentBlue)
            }
            VStack(spacing: 8) {
                mini("paperplane.fill", "航海模式", $m.prefs.sailing)
                mini("bolt.badge.automatic", "自动放电", $m.prefs.autoDischarge)
                mini("flame", "过热保护", $m.prefs.heatProtection)
                mini("plus.circle", "充满一次", $m.prefs.topUp)
            }
            if !model.prefs.menuItems.isEmpty {
                Divider()
                FlowLayout(spacing: 6) {
                    ForEach(model.prefs.menuItems) { k in
                        if let t = model.menuText(k) {
                            Label(t, systemImage: k.icon).font(.system(size: 11.5, weight: .medium))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(Color.primary.opacity(0.07)))
                        }
                    }
                }
            }
            if !model.helperRunning {
                Label("辅助程序未运行", systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(.orange)
            }
            Divider()
            HStack {
                Button("打开电池管家") {
                    openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 300)
    }

    private func mini(_ icon: String, _ title: String, _ b: Binding<Bool>) -> some View {
        HStack {
            Label(title, systemImage: icon).font(.system(size: 13))
            Spacer()
            Toggle("", isOn: b).toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
    }
}
