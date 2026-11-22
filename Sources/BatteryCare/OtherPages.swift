import SwiftUI
import Shared

// MARK: - 睡眠行为

struct SleepView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var m = model
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(icon: "moon.zzz", title: "禁用睡眠")
            Card {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 6) {
                        Text("在以下情况下，电池管家会阻止睡眠：").font(.system(size: 13)).foregroundStyle(.secondary)
                        HelpButton(text: "Mac 睡眠后后台程序无法运行。为保证校准和放电过程能正确结束，这些阶段会临时阻止睡眠（包括合盖）。")
                    }
                    SettingLabel(icon: "slider.vertical.3", title: "校准模式期间（必要）")
                    SettingLabel(icon: "minus.circle", title: "放电期间，包括合盖时（必要）")
                    SettingRow(icon: "bed.double.fill", title: "充到限制前禁用睡眠（可选）",
                               help: "插着电源充电时，在达到充电限制之前保持唤醒，确保充到上限后能被及时停住。") {
                        Toggle("", isOn: $m.prefs.disableSleepUntilLimit).toggleStyle(.switch).labelsHidden().controlSize(.large)
                    }
                    Text("电池管家阻止睡眠时的屏幕设置").font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 4)
                    SettingRow(icon: "display", title: "不活动时关闭显示屏") {
                        Picker("", selection: $m.prefs.displaySleep) {
                            ForEach(DisplaySleep.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.labelsHidden().fixedSize()
                    }
                }
            }
            ToggleRow(icon: "moon.fill", title: "睡眠时停止充电",
                      help: "Mac 进入睡眠前暂停充电，睡眠期间不会把电池充过上限。适配器模式下（macOS 27 固件）为安全起见睡眠时总会恢复供电，此选项不生效。",
                      isOn: $m.prefs.stopOnSleep).padding(.top, 14)
            ToggleRow(icon: "power", title: "应用程序关闭时停止充电",
                      help: "退出电池管家后，后台辅助程序会保持暂停充电状态，而不是恢复到系统默认的充满。", isOn: $m.prefs.appClosedStop)
        }
    }
}

// MARK: - 能源使用

struct EnergyView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var m = model
        VStack(alignment: .leading, spacing: 20) {
            SettingRow(icon: "battery.25percent", title: "低电量模式",
                       help: "通过系统 pmset 设置低电量模式。“仅使用电池时”会在拔掉电源时自动开启。需要辅助程序。") {
                Picker("", selection: $m.prefs.lowPowerMode) {
                    ForEach(LowPowerMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 200)
            }
            ToggleRow(icon: "arrow.clockwise.circle", title: "后台仪表板更新",
                      help: "主窗口关闭时继续记录电量历史。关闭后可略微减少后台活动。", isOn: $m.prefs.backgroundDashboard)
            SettingRow(icon: "bolt", title: "高功耗的应用程序", help: "列出当前占用 CPU 超过阈值的进程，它们是耗电的主要来源。") {
                Picker("", selection: $m.prefs.highPower) {
                    ForEach(HighPowerThreshold.allCases, id: \.self) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 220)
            }
            let list = model.processes.filter { $0.cpu >= Double(model.prefs.highPower.rawValue) }
            Card(padding: 8) {
                if list.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.system(size: 20))
                        Text(model.processes.isEmpty ? "正在分析…" : "没有发现高功耗的应用程序").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    VStack(spacing: 0) {
                        ForEach(list) { p in
                            HStack(spacing: 12) {
                                if let icon = p.icon { Image(nsImage: icon).resizable().frame(width: 26, height: 26) }
                                else { Image(systemName: "gearshape.2").frame(width: 26, height: 26).foregroundStyle(.secondary) }
                                Text(p.name).font(.system(size: 14, weight: .medium))
                                Spacer()
                                Capsule().fill(Color.orange.opacity(0.15)).frame(width: 120, height: 8)
                                    .overlay(alignment: .leading) { Capsule().fill(Color.orange).frame(width: min(120, 120 * p.cpu / 200), height: 8) }
                                Text(String(format: "%.0f%%", p.cpu)).font(.system(size: 13, weight: .semibold).monospacedDigit()).frame(width: 52, alignment: .trailing)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            if p.id != list.last?.id { Divider().padding(.leading, 52) }
                        }
                    }
                }
            }
        }
        .onAppear { model.refreshProcesses() }
    }
}

// MARK: - 定时设置

struct ScheduleView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var m = model
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(icon: "checklist", title: "任务")
            Card(padding: 16) {
                VStack(spacing: 14) {
                    if m.prefs.tasks.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "calendar.badge.plus").font(.system(size: 30)).foregroundStyle(.secondary)
                            Text("还没有任务，点击下方 ＋ 添加").foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, minHeight: 140)
                    }
                    ForEach($m.prefs.tasks) { $task in TaskEditor(task: $task) { m.prefs.tasks.removeAll { $0.id == task.id } } }
                }
                .frame(minHeight: 200, alignment: .top)
            }
            HStack(spacing: 12) {
                Button { withAnimation { m.prefs.tasks.append(ScheduledTask()) } } label: { Image(systemName: "plus.square") }
                    .buttonStyle(CircleButtonStyle())
                Button { withAnimation { m.prefs.tasks.removeAll() } } label: { Label("全部清除", systemImage: "trash") }
                    .buttonStyle(SoftButtonStyle(destructive: true))
                Spacer()
                Text("在下次可能时执行错过的任务：").font(.system(size: 14))
                Toggle("", isOn: $m.prefs.runMissedTasks).toggleStyle(.switch).labelsHidden().controlSize(.large)
            }
            SectionHeader(icon: "list.bullet.rectangle", title: "任务历史").padding(.top, 16)
            Card(padding: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    if m.prefs.taskHistory.isEmpty { Text("暂无记录").foregroundStyle(.secondary) }
                    ForEach(m.prefs.taskHistory.prefix(30)) { log in
                        HStack(spacing: 16) {
                            Text(log.date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute().second()))
                                .font(.system(size: 13.5).monospacedDigit())
                            Text(log.name).font(.system(size: 13.5, weight: .semibold))
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            Text(log.action).font(.system(size: 13.5))
                            if log.skipped { Text("已跳过").font(.caption).foregroundStyle(.orange) }
                        }
                    }
                }
                .frame(minHeight: 120, alignment: .topLeading)
            }
            Button { m.prefs.taskHistory.removeAll() } label: { Label("清除所有任务历史记录", systemImage: "trash") }
                .buttonStyle(SoftButtonStyle(destructive: true))
        }
    }
}

struct TaskEditor: View {
    @Binding var task: ScheduledTask
    let onDelete: () -> Void
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
            GridRow {
                Text("名称：").bold()
                TextField("名称", text: $task.name).textFieldStyle(.roundedBorder).frame(width: 220)
                Spacer()
                HStack { Text("启用：").bold(); Toggle("", isOn: $task.enabled).toggleStyle(.switch).labelsHidden() }
            }
            GridRow {
                Text("操作：").bold()
                HStack {
                    Picker("", selection: $task.action) { ForEach(TaskAction.allCases, id: \.self) { Text($0.title).tag($0) } }
                        .labelsHidden().frame(width: 220)
                    if task.action == .setLimit { NumberBox(value: $task.value, range: 20...100, width: 56); Text("%") }
                }
            }
            GridRow {
                Text("重复：").bold()
                Picker("", selection: $task.rule) { ForEach(RepeatRule.allCases, id: \.self) { Text($0.title).tag($0) } }
                    .labelsHidden().frame(width: 220)
            }
            GridRow {
                Text("开始：").bold()
                DatePicker("", selection: $task.start).labelsHidden().datePickerStyle(.stepperField)
                    .onChange(of: task.start) { _, _ in task.lastRun = nil }
                Spacer()
                Button(action: onDelete) { Image(systemName: "trash") }.buttonStyle(CircleButtonStyle())
            }
            if let next = task.nextDue {
                GridRow { Text(""); Text("下次执行：\(next.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .font(.system(size: 14))
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.primary.opacity(0.08)))
    }
}

// MARK: - 捷径

struct ShortcutsView: View {
    @Environment(AppModel.self) private var model
    @State private var copied: String?
    private var helperCLI: String { (Bundle.main.resourcePath ?? "/Applications/BatteryCare.app/Contents/Resources") + "/batterycare-helper" }
    private var rows: [(String, String, String)] {
        [("充满一次", "将充电限制设为 100% 并开始充电。", "open batterycare://topup"),
         ("暂停充电", "将充电限制设置为当前电量，从而暂停充电。", "open batterycare://pause"),
         ("开始放电", "开始将电池放电至设定的充电限制。", "open batterycare://discharge"),
         ("启动校准模式", "启动校准程序，重新校准电池。", "open batterycare://calibrate"),
         ("设置充电限制", "设置特定的充电限制百分比（示例 80）。", "open batterycare://limit/80"),
         ("开启低电量模式", "把低电量模式设为“始终开启”。", "open batterycare://lowpower/on"),
         ("关闭低电量模式", "把低电量模式设为“始终关闭”。", "open batterycare://lowpower/off"),
         ("获取电池百分比", "返回当前电池百分比。", "'\(helperCLI)' get percent"),
         ("获取充电限制", "返回当前设置的充电限制。", "'\(helperCLI)' get limit"),
         ("获取状态", "返回当前状态（charging / paused / discharging…）。", "'\(helperCLI)' get state"),
         ("获取温度", "返回电池当前温度（°C）。", "'\(helperCLI)' get temperature")]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionHeader(icon: "square.stack.3d.up", title: "可用于快捷指令的命令",
                              help: "在“快捷指令”App 中添加“运行 Shell 脚本”操作，粘贴下面的命令即可。open 开头的命令也可以直接在终端运行。")
                Spacer()
                Button("打开快捷指令") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app")) }
                    .buttonStyle(SoftButtonStyle())
            }
            Card(padding: 10) {
                VStack(spacing: 0) {
                    ForEach(rows.indices, id: \.self) { i in
                        let r = rows[i]
                        HStack(alignment: .top, spacing: 16) {
                            Text(r.0).font(.system(size: 14.5, weight: .semibold)).frame(width: 130, alignment: .leading)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(r.1).font(.system(size: 14))
                                Text(r.2).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(r.2, forType: .string)
                                withAnimation { copied = r.0 }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { if copied == r.0 { copied = nil } } }
                            } label: {
                                Image(systemName: copied == r.0 ? "checkmark" : "doc.on.doc").foregroundStyle(copied == r.0 ? Color.green : Color.secondary)
                            }.buttonStyle(.plain).help("复制命令")
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        if i < rows.count - 1 { Divider().padding(.horizontal, 14) }
                    }
                }
            }
        }
    }
}

// MARK: - 悬浮窗

struct OverlaySettingsView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var m = model
        VStack(alignment: .leading, spacing: 20) {
            ToggleRow(icon: "rectangle.inset.topright.filled", title: "显示悬浮窗", help: "在所有窗口之上显示一个小浮窗，实时显示电量和充电状态。",
                      isOn: Binding(get: { model.overlayVisible }, set: { model.setOverlay($0) }))
            ToggleRow(icon: "eye", title: "启动时显示", help: "打开电池管家时自动显示悬浮窗。", isOn: $m.prefs.overlayOnLaunch)
            ToggleRow(icon: "percent", title: "显示百分比", help: "在悬浮窗中显示电量百分比数字。", isOn: $m.prefs.overlayPercent)
            Button(model.overlayEditing ? "完成编辑" : "在编辑模式下打开") {
                model.overlayEditing ? model.setOverlay(true, edit: false) : model.setOverlay(true, edit: true)
            }
            .buttonStyle(SoftButtonStyle(prominent: model.overlayEditing, minWidth: 300))
            Text("编辑模式下可以拖动悬浮窗到任意位置；平时它不会拦截鼠标点击。").font(.system(size: 12.5)).foregroundStyle(.secondary)
        }
    }
}

struct OverlayHUD: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 10) {
            BatteryGlyph(percent: model.displayPercent, limit: model.effectiveLimit, color: model.stateColor == .secondary ? .green : model.stateColor)
                .frame(width: 44, height: 22)
            if model.prefs.overlayPercent {
                Text("\(model.displayPercent)%").font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
            }
            Image(systemName: model.stateIcon).foregroundStyle(model.stateColor == .secondary ? Color.primary : model.stateColor)
            if model.overlayEditing {
                Button("完成") { model.setOverlay(true, edit: false) }.buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(model.overlayEditing ? Color.accentBlue : Color.primary.opacity(0.1), lineWidth: model.overlayEditing ? 2 : 1))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .frame(width: 240, height: 70)
    }
}

// MARK: - 其他

struct OtherView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var m = model
        VStack(alignment: .leading, spacing: 20) {
            ToggleRow(icon: "gauge.with.dots.needle.67percent", title: "硬件电池百分比",
                      help: "显示电池芯片报告的真实电量（当前容量 ÷ 满充容量），而不是 macOS 经过平滑处理的百分比。", isOn: $m.prefs.hardwarePercent)
            SettingRow(icon: "dock.rectangle", title: "程序坞图标",
                       help: "“窗口打开时显示”：关闭窗口、在程序坞中选择退出或按 ⌘Q 时，电池管家只会隐藏到菜单栏继续运行，不占用程序坞。要完全退出，请使用菜单栏面板里的“退出”或按 ⌥⌘Q。") {
                Picker("", selection: Binding(get: { m.prefs.dockPolicy }, set: { v in
                    m.prefs.dockPolicy = v
                    if v == .never && m.prefs.iconStyle == .hidden { m.prefs.iconStyle = .app }
                })) { ForEach(DockPolicy.allCases, id: \.self) { Text($0.title).tag($0) } }
                .labelsHidden().fixedSize()
            }
            ToggleRow(icon: "drop", title: "降低透明度", help: "侧边栏使用纯色背景，而不是半透明毛玻璃。", isOn: $m.prefs.reduceTransparency)
            SettingRow(icon: "circle.lefthalf.filled", title: "外观模式") {
                HStack(spacing: 18) {
                    ForEach(Appearance.allCases, id: \.self) { a in
                        Button { m.prefs.appearance = a } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle().fill(a == .dark ? Color.black : Color.white)
                                    if a == .system { Circle().trim(from: 0.25, to: 0.75).fill(Color.black).rotationEffect(.degrees(0)) }
                                }
                                .frame(width: 34, height: 34)
                                .overlay(Circle().stroke(m.prefs.appearance == a ? Color.accentBlue : Color.primary.opacity(0.2), lineWidth: m.prefs.appearance == a ? 3 : 1))
                                Text(a.title).font(.system(size: 11.5)).foregroundStyle(m.prefs.appearance == a ? Color.accentBlue : .secondary)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
            SectionHeader(icon: "light.beacon.max", title: "MagSafe LED").padding(.top, 8)
            Card {
                VStack(spacing: 16) {
                    SettingRow(icon: "lightbulb", title: "LED 设置") {
                        Picker("", selection: $m.prefs.ledMode) { ForEach(LEDMode.allCases, id: \.self) { Text($0.title).tag($0) } }
                            .labelsHidden().fixedSize()
                    }
                    SettingRow(icon: "switch.2", title: "指示充电限制", help: "达到充电限制、暂停充电时，MagSafe 指示灯显示绿色。") {
                        Toggle("", isOn: $m.prefs.ledIndicateLimit).toggleStyle(.switch).labelsHidden().controlSize(.large)
                    }
                    SettingRow(icon: "sparkles", title: "放电期间闪烁橙色", help: "主动放电时让 MagSafe 指示灯橙色闪烁。") {
                        Toggle("", isOn: $m.prefs.ledBlinkDischarge).toggleStyle(.switch).labelsHidden().controlSize(.large)
                    }
                }
                .disabled(model.prefs.ledMode == .off && false)
            }
            SectionHeader(icon: "ellipsis.circle", title: "其他").padding(.top, 8)
            Card {
                VStack(alignment: .leading, spacing: 18) {
                    UpdateRow()
                    SettingRow(icon: "play", title: "开机自启", help: "登录 macOS 时自动启动电池管家。建议把应用放在“应用程序”文件夹中。") {
                        Toggle("", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                            .toggleStyle(.switch).labelsHidden().controlSize(.large)
                    }
                }
            }
            SectionHeader(icon: "hare", title: "快捷功能").padding(.top, 8)
            Card {
                Grid(horizontalSpacing: 40, verticalSpacing: 14) {
                    GridRow {
                        Button("简介") { NSApp.orderFrontStandardAboutPanel(nil); NSApp.activate(ignoringOtherApps: true) }
                            .buttonStyle(SoftButtonStyle(minWidth: 240))
                        Button("保存调试文件") { model.saveDebugFile() }.buttonStyle(SoftButtonStyle(minWidth: 240))
                    }
                    GridRow {
                        Button("恢复默认设置") { model.resetDefaults() }.buttonStyle(SoftButtonStyle(minWidth: 240))
                        Button("删除电池管家") { model.uninstallEverything() }.buttonStyle(SoftButtonStyle(destructive: true, minWidth: 240))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
