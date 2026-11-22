import SwiftUI

struct UpdateSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let u = Updater.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("发现新版本").font(.system(size: 19, weight: .bold))
                    Text("电池管家 \(u.latest?.version ?? "") 已发布，你当前使用的是 \(Updater.currentVersion)。")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            ScrollView {
                Text(notes).font(.system(size: 13)).lineSpacing(3).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
            .frame(height: 240)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.05)))
            if case .failed(let msg) = u.phase {
                Label(msg, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12.5)).foregroundStyle(.red)
            }
            HStack {
                Button("发布页") { u.openReleasePage() }.buttonStyle(SoftButtonStyle())
                Spacer()
                Button("稍后") { dismiss() }.buttonStyle(SoftButtonStyle())
                Button { u.downloadAndInstall() } label: {
                    HStack(spacing: 8) {
                        if u.phase == .downloading || u.phase == .installing { ProgressView().controlSize(.small).tint(.white) }
                        Text(u.phase == .downloading ? "正在下载…" : u.phase == .installing ? "正在安装…" : "下载并安装")
                    }
                }
                .buttonStyle(SoftButtonStyle(prominent: true))
                .disabled(u.phase == .downloading || u.phase == .installing)
            }
            Text("安装后应用会自动重启。").font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        .padding(24).frame(width: 520)
    }

    private var notes: AttributedString {
        let raw = u.latest?.body ?? "（无更新说明）"
        let cleaned = raw.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("```") }
            .map { line -> String in
                var l = String(line)
                while l.hasPrefix("#") { l.removeFirst() }
                if l.hasPrefix("- ") { l = "•  " + l.dropFirst(2) }
                if l.hasPrefix("> ") { l = String(l.dropFirst(2)) }
                return l.trimmingCharacters(in: .init(charactersIn: " "))
            }.joined(separator: "\n")
        return (try? AttributedString(markdown: cleaned, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(cleaned)
    }
}

/// Row shown in 其他 → 其他.
struct UpdateRow: View {
    private let u = Updater.shared
    var body: some View {
        @Bindable var u = u
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Button { u.updateAvailable ? (u.showSheet = true) : u.check(userInitiated: true) } label: {
                    HStack(spacing: 8) {
                        if u.phase == .checking { ProgressView().controlSize(.small) }
                        Text(u.updateAvailable ? "更新到 \(u.latest?.version ?? "")" : "检查更新")
                    }
                }
                .buttonStyle(SoftButtonStyle(prominent: u.updateAvailable, minWidth: 240))
                .disabled(u.phase == .checking)
                Spacer()
                Text("自动检查").font(.system(size: 14))
                Toggle("", isOn: $u.autoCheck).toggleStyle(.switch).labelsHidden().controlSize(.large)
            }
            Text(statusText).font(.system(size: 12.5)).foregroundStyle(statusColor)
        }
    }
    private var statusText: String {
        switch u.phase {
        case .checking: return "正在检查…"
        case .upToDate: return "已是最新版本（\(Updater.currentVersion)）" + checked
        case .available, .downloading, .installing: return "发现新版本 \(u.latest?.version ?? "")，当前 \(Updater.currentVersion)"
        case .failed(let m): return "检查失败：\(m)"
        case .idle: return "当前版本 \(Updater.currentVersion)" + checked
        }
    }
    private var checked: String { u.lastCheck.map { " · 上次检查 \($0.formatted(.relative(presentation: .named)))" } ?? "" }
    private var statusColor: Color {
        switch u.phase { case .failed: .red; case .available: Color.accentBlue; default: .secondary }
    }
}

/// Compact banner for the dashboard.
struct UpdateBanner: View {
    private let u = Updater.shared
    var body: some View {
        if u.updateAvailable {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 22)).foregroundStyle(Color.accentBlue)
                Text("电池管家 \(u.latest?.version ?? "") 已发布").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("查看更新") { u.showSheet = true }.buttonStyle(SoftButtonStyle(prominent: true))
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.accentBlue.opacity(0.08)))
        }
    }
}
