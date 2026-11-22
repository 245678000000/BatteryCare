import SwiftUI

struct ChargeControlView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var m = model
        VStack(alignment: .leading, spacing: 20) {
            HelperBanner()
            Card(padding: 20) {
                VStack(spacing: 14) {
                    SettingRow(icon: "battery.75percent", title: "充电限制",
                               help: "电池充到这个百分比后停止充电。长期插电使用时，把电量保持在 80% 以下能明显减缓电池老化。") {
                        HStack(spacing: 6) {
                            NumberBox(value: $m.prefs.limit, range: 20...100)
                            Text("%").font(.system(size: 16, weight: .medium))
                        }
                    }
                    Slider(value: Binding(get: { Double(m.prefs.limit) }, set: { m.prefs.limit = Int($0.rounded()) }), in: 20...100, step: 5) {
                        EmptyView()
                    } minimumValueLabel: { Text("20%").font(.caption).foregroundStyle(.secondary) }
                      maximumValueLabel: { Text("100%").font(.caption).foregroundStyle(.secondary) }
                    .tint(Color.accentBlue)
                    if model.adapterMode {
                        Label("适配器模式：达到上限后断开外接电源、由电池供电，回落约 \(model.prefs.sailing ? model.prefs.sailingDiff : 3)% 后恢复供电。",
                              systemImage: "info.circle")
                            .font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            ToggleRow(icon: "bolt.badge.automatic", title: "自动放电",
                      help: "当电量高于充电限制时（即使接着电源），主动让电池放电，直到降到限制值。", isOn: $m.prefs.autoDischarge)
            ToggleRow(icon: "paperplane.fill", title: "航海模式",
                      help: "达到上限后，电量要先下降一段（差异值）才会重新开始充电，避免在上限附近反复启停充电造成微循环。", isOn: $m.prefs.sailing)
            if m.prefs.sailing {
                Card(padding: 18) {
                    HStack(spacing: 10) {
                        Spacer()
                        Text("差异：").font(.system(size: 15, weight: .medium))
                        NumberBox(value: $m.prefs.sailingDiff, range: 1...30)
                        Text("%").font(.system(size: 15, weight: .medium))
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Text("将航海至 \(max(m.prefs.limit - m.prefs.sailingDiff, 0))%。").font(.system(size: 15, weight: .medium))
                        Spacer()
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            ToggleRow(icon: "flame", title: "过热保护",
                      help: "电池温度达到设定值时暂停充电，温度下降后自动恢复。高温充电是电池老化的主要原因之一。", isOn: $m.prefs.heatProtection)
            if m.prefs.heatProtection {
                Card(padding: 18) {
                    HStack(spacing: 10) {
                        Spacer()
                        Text("最高温度").font(.system(size: 15, weight: .medium))
                        NumberBox(value: $m.prefs.maxTemp, range: 25...50)
                        Text("°C").font(.system(size: 15, weight: .medium))
                        Text("当前温度：\(model.battery.temperature.map { String(format: "%.1f°C", $0) } ?? "—")")
                            .font(.system(size: 15, weight: .medium)).padding(.leading, 14)
                            .foregroundStyle((model.battery.temperature ?? 0) >= Double(m.prefs.maxTemp) ? Color.orange : Color.primary)
                        Spacer()
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            ToggleRow(icon: "plus.circle", title: "充满一次（Top Up）",
                      help: "临时把上限提到 100%，充满后自动恢复原来的限制。适合出门前使用。", isOn: $m.prefs.topUp)

            CalibrationSection().padding(.top, 14)
        }
        .animation(.spring(duration: 0.35), value: m.prefs.sailing)
        .animation(.spring(duration: 0.35), value: m.prefs.heatProtection)
    }
}

struct CalibrationSection: View {
    @Environment(AppModel.self) private var model
    private let steps: [(String, Double, Color, String)] = [
        ("充电至\n100%", 1.0, .green, "plus"),
        ("放电至\n10%", 0.18, .orange, "minus"),
        ("充电至\n100%", 1.0, .green, "plus"),
        ("保持\n1 小时", 1.0, .blue, "pause.fill"),
        ("放电至\n上限", 0.8, .orange, "minus"),
    ]
    var body: some View {
        let stage = model.calibrationStage
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SettingLabel(icon: "slider.vertical.3", title: "校准模式",
                             help: "完整地充满—放空—充满一次，让电池管理芯片重新校准电量读数。校准期间会阻止睡眠，过程可能需要数小时，需要一直连接电源。")
                Spacer()
                Button {
                    stage == nil ? model.startCalibration() : model.stopCalibration()
                } label: {
                    Label(stage == nil ? "开始校准" : "停止校准", systemImage: stage == nil ? "play" : "stop.fill")
                }
                .buttonStyle(SoftButtonStyle(destructive: stage != nil, minWidth: 220))
                .disabled(!model.helperRunning)
            }
            Card(padding: 18) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(steps.indices, id: \.self) { i in
                        let s = steps[i]
                        VStack(spacing: 8) {
                            MiniBattery(fill: s.1, color: s.2, symbol: s.3, active: stage == i + 1, done: (stage ?? 0) > i + 1)
                            Text(s.0).font(.system(size: 12.5, weight: stage == i + 1 ? .semibold : .regular))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(stage == i + 1 ? Color.accentBlue : Color.primary)
                        }
                        .frame(maxWidth: .infinity)
                        if i < steps.count - 1 {
                            Image(systemName: "arrow.right").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary).padding(.top, 20)
                        }
                    }
                }
                .animation(.spring(duration: 0.4), value: stage)
            }
            HStack {
                Spacer()
                Text("上次校准：\(model.helper?.lastCalibration.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "-")")
                    .font(.system(size: 14, weight: .medium))
            }
        }
    }
}
