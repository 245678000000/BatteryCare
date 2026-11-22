import SwiftUI
import Charts

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let b = model.battery
        VStack(alignment: .leading, spacing: 22) {
            HelperBanner()
            hero
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14)], spacing: 14) {
                StatTile(icon: "heart.fill", tint: .pink, title: "电池健康", value: String(format: "%.1f%%", b.health),
                         sub: "\(b.maxCapacity) / \(b.designCapacity) mAh")
                StatTile(icon: "arrow.triangle.2.circlepath", tint: .purple, title: "循环次数", value: "\(b.cycleCount)",
                         sub: "设计寿命 \(b.designCycleCount) 次")
                StatTile(icon: "thermometer.medium", tint: tempColor(b.temperature), title: "温度",
                         value: b.temperature.map { String(format: "%.1f°C", $0) } ?? "—", sub: model.prefs.heatProtection ? "过热保护 \(model.prefs.maxTemp)°C" : "过热保护已关闭")
                StatTile(icon: "gauge.with.dots.needle.50percent", tint: .orange, title: "功率",
                         value: String(format: "%+.1f W", b.power), sub: b.power >= 0 ? "流入电池" : "电池输出")
                StatTile(icon: "bolt.fill", tint: .yellow, title: "电压 / 电流",
                         value: String(format: "%.2f V", b.voltage), sub: String(format: "%+.2f A", b.amperage))
                StatTile(icon: "powerplug.fill", tint: .teal, title: "电源适配器",
                         value: b.adapterWatts.map { "\($0) W" } ?? (b.externalConnected ? "已连接" : "未连接"),
                         sub: b.adapterName ?? (b.externalConnected ? "—" : "使用电池供电"))
            }
            HistoryCard()
        }
    }

    private var hero: some View {
        let b = model.battery
        return Card(padding: 26) {
            HStack(spacing: 30) {
                BatteryGlyph(percent: model.displayPercent, limit: model.effectiveLimit, color: model.stateColor == .secondary ? .green : model.stateColor,
                             symbol: model.state == .charging ? "bolt.fill" : model.state == .paused ? "pause.fill" : nil)
                    .frame(width: 190, height: 92)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(model.displayPercent)").font(.system(size: 58, weight: .bold, design: .rounded)).contentTransition(.numericText())
                        Text("%").font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: model.stateIcon)
                        Text(model.stateTitle)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.stateColor == .secondary ? Color.primary : model.stateColor)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill((model.stateColor == .secondary ? Color.primary : model.stateColor).opacity(0.12)))
                    HStack(spacing: 16) {
                        Label("上限 \(model.effectiveLimit)%", systemImage: "chart.bar.xaxis")
                        if let m = b.minutesRemaining {
                            Label(b.isCharging ? "充满还需 \(fmt(m))" : "剩余 \(fmt(m))", systemImage: "clock")
                        }
                    }
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private func fmt(_ m: Int) -> String { m >= 60 ? "\(m / 60) 小时 \(m % 60) 分" : "\(m) 分钟" }
    private func tempColor(_ t: Double?) -> Color { guard let t else { return .gray }; return t > 40 ? .red : t > 35 ? .orange : .blue }
}

struct StatTile: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    let sub: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.gradient))
                Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
            }
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(sub).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.card).shadow(color: .black.opacity(0.05), radius: 10, y: 3))
    }
}

struct HistoryCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(icon: "chart.xyaxis.line", title: "电量历史（24 小时）")
                    Spacer()
                    HStack(spacing: 4) {
                        Rectangle().fill(Color.primary.opacity(0.4)).frame(width: 14, height: 2)
                        Text("充电上限").font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                }
                if model.history.count < 2 {
                    Text("正在收集数据…每 2 分钟记录一次").font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    Chart {
                        ForEach(model.history) { p in
                            AreaMark(x: .value("时间", p.date), y: .value("电量", p.percent))
                                .foregroundStyle(LinearGradient(colors: [Color.accentBlue.opacity(0.35), Color.accentBlue.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.monotone)
                            LineMark(x: .value("时间", p.date), y: .value("电量", p.percent))
                                .foregroundStyle(Color.accentBlue).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .interpolationMethod(.monotone)
                        }
                        RuleMark(y: .value("上限", model.effectiveLimit))
                            .foregroundStyle(Color.primary.opacity(0.4)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { v in AxisGridLine(); AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%") } } }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.hour().minute()) } }
                    .frame(height: 190)
                }
            }
        }
    }
}
