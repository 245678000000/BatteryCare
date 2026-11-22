import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var m = model
        HStack(spacing: 0) {
            Sidebar().frame(width: 232)
            Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1)
            ZStack {
                LinearGradient(colors: [.paneTop, .paneBottom], startPoint: .top, endPoint: .bottom)
                ScrollView {
                    page
                        .padding(.horizontal, 34).padding(.top, 40).padding(.bottom, 34)
                        .frame(maxWidth: 820)
                        .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.automatic)
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $m.showHelperSheet) { HelperSheet().environment(model) }
        .sheet(isPresented: Binding(get: { Updater.shared.showSheet }, set: { Updater.shared.showSheet = $0 })) { UpdateSheet() }
        .alert("提示", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button("好") {}
        } message: { Text(model.alert ?? "") }
    }

    @ViewBuilder private var page: some View {
        switch model.selection {
        case .dashboard: DashboardView()
        case .charge: ChargeControlView()
        case .sleep: SleepView()
        case .energy: EnergyView()
        case .schedule: ScheduleView()
        case .shortcuts: ShortcutsView()
        case .overlay: OverlaySettingsView()
        case .menubar: MenuBarSettingsView()
        case .other: OtherView()
        }
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var m = model
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 50)
            ForEach(Array(Page.sections.enumerated()), id: \.offset) { i, section in
                if let title = section.0 {
                    Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.leading, 20).padding(.top, i == 1 ? 14 : 12).padding(.bottom, 4)
                }
                ForEach(section.1) { page in SidebarItem(page: page, selected: model.selection == page) { model.selection = page } }
                if i == 0 { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1).padding(.horizontal, 6).padding(.top, 10) }
            }
            Spacer()
            HStack(spacing: 14) {
                Button { m.prefs.enabled.toggle() } label: { Image(systemName: "power") }
                    .buttonStyle(CircleButtonStyle(tint: model.prefs.enabled ? .green : .secondary))
                    .help(model.prefs.enabled ? "暂停电池管理（恢复系统默认充电）" : "恢复电池管理")
                Button { model.showHelperSheet = true } label: {
                    Image(systemName: "gearshape")
                        .overlay(alignment: .topTrailing) {
                            Circle().fill(model.helperRunning ? Color.green : Color.orange).frame(width: 9, height: 9).offset(x: 6, y: -5)
                        }
                }
                .buttonStyle(CircleButtonStyle())
                .help("辅助程序")
            }
            .padding(.leading, 18).padding(.bottom, 20)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            if model.prefs.reduceTransparency { Color.sidebarBG } else { VisualEffect(material: .sidebar) }
        }
    }
}

struct SidebarItem: View {
    let page: Page
    let selected: Bool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: page.icon).font(.system(size: 16, weight: .medium)).frame(width: 24)
                Text(page.title).font(.system(size: 15, weight: selected ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(selected ? Color.accentBlue : Color.primary)
            .padding(.horizontal, 12).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.selectedRow : (hover ? Color.selectedRow.opacity(0.5) : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .padding(.vertical, 2)
    }
}

/// Shown on pages that need the root helper when it isn't running.
struct HelperBanner: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if model.helperRunning && model.helperOutdated {
            HStack(spacing: 14) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill").font(.system(size: 24)).foregroundStyle(Color.accentBlue)
                VStack(alignment: .leading, spacing: 3) {
                    Text("辅助程序有新版本").font(.system(size: 14, weight: .semibold))
                    Text("应用已更新，后台辅助程序也需要更新才能使用最新的充电控制逻辑。").font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("更新") { model.installHelper() }.buttonStyle(SoftButtonStyle(prominent: true))
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.accentBlue.opacity(0.08)))
        } else if !model.helperRunning {
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.shield.fill").font(.system(size: 24)).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.helperInstalled ? "辅助程序未响应" : "需要安装辅助程序").font(.system(size: 14, weight: .semibold))
                    Text("充电控制需要一个后台辅助程序写入硬件（SMC），安装时需要输入管理员密码。")
                        .font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.helperInstalled ? "重新安装" : "安装") { model.installHelper() }.buttonStyle(SoftButtonStyle(prominent: true))
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.orange.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.orange.opacity(0.25)))
        }
    }
}

struct HelperSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "cpu").font(.system(size: 22)).foregroundStyle(Color.accentBlue)
                Text("后台辅助程序").font(.system(size: 18, weight: .bold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
            Card(padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    row("状态", model.helperRunning ? "运行中" : (model.helperInstalled ? "已安装 · 未响应" : "未安装"),
                        model.helperRunning ? .green : .orange)
                    row("控制方式", backendTitle, .primary)
                    if let msg = model.helper?.message { row("错误", msg, .red) }
                    row("日志", "/Users/Shared/BatteryCare/helper.log", .secondary)
                }
            }
            if model.adapterMode {
                Text("此 Mac 的固件（macOS 27）已锁定“暂停充电”接口。电池管家改用“断开电源适配器”的方式保持充电上限：达到上限后由电池供电，电量回落几个百分点后恢复外接电源。睡眠前会自动恢复供电。")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if model.helperInstalled {
                    Button("卸载") { model.uninstallHelper() }.buttonStyle(SoftButtonStyle(destructive: true))
                }
                Spacer()
                Button(model.helperOutdated ? "更新" : model.helperInstalled ? "重新安装" : "安装") { model.installHelper() }.buttonStyle(SoftButtonStyle(prominent: true))
            }
        }
        .padding(24).frame(width: 460)
    }
    private var backendTitle: String {
        guard let b = model.helper?.backend else { return "—" }
        if b.hasPrefix("adapter") { return "适配器模式（CHIE）" }
        if b == "none" { return "不支持" }
        return "直接控制（\(b)）"
    }
    private func row(_ k: String, _ v: String, _ c: Color) -> some View {
        HStack(alignment: .top) { Text(k).foregroundStyle(.secondary).frame(width: 70, alignment: .leading); Text(v).foregroundStyle(c).textSelection(.enabled) }
            .font(.system(size: 13.5))
    }
}
