import SwiftUI

extension Color {
    static func dyn(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
    static let sidebarBG = dyn(NSColor(white: 0.962, alpha: 1), NSColor(white: 0.135, alpha: 1))
    static let paneTop = dyn(.white, NSColor(white: 0.115, alpha: 1))
    static let paneBottom = dyn(NSColor(white: 0.925, alpha: 1), NSColor(white: 0.075, alpha: 1))
    static let card = dyn(.white, NSColor(white: 0.175, alpha: 1))
    static let field = dyn(.white, NSColor(white: 0.23, alpha: 1))
    static let fieldStroke = dyn(NSColor(white: 0.86, alpha: 1), NSColor(white: 0.32, alpha: 1))
    static let soft = dyn(NSColor(white: 0.88, alpha: 1), NSColor(white: 0.26, alpha: 1))
    static let selectedRow = dyn(NSColor(white: 0, alpha: 0.065), NSColor(white: 1, alpha: 0.09))
    static let accentBlue = Color(red: 0.19, green: 0.45, blue: 0.96)
}

struct Card<Content: View>: View {
    var padding: CGFloat = 22
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.card)
                .shadow(color: .black.opacity(0.06), radius: 14, y: 4))
    }
}

struct HelpButton: View {
    let text: String
    @State private var show = false
    var body: some View {
        Button { show.toggle() } label: {
            Image(systemName: "questionmark.circle").font(.system(size: 16)).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $show, arrowEdge: .bottom) {
            Text(text).font(.callout).lineSpacing(3).padding(16).frame(width: 280, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SettingLabel: View {
    let icon: String
    let title: String
    var help: String? = nil
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 16, weight: .medium)).frame(width: 24)
            Text(title).font(.system(size: 15, weight: .semibold))
            if let help { HelpButton(text: help) }
        }
    }
}

struct SettingRow<Trailing: View>: View {
    let icon: String
    let title: String
    var help: String? = nil
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack { SettingLabel(icon: icon, title: title, help: help); Spacer(minLength: 16); trailing }
            .frame(minHeight: 34)
    }
}

struct ToggleRow: View {
    let icon: String
    let title: String
    var help: String? = nil
    @Binding var isOn: Bool
    var body: some View {
        SettingRow(icon: icon, title: title, help: help) {
            Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden().controlSize(.large)
        }
    }
}

struct SectionHeader: View {
    let icon: String
    let title: String
    var help: String? = nil
    var body: some View { SettingLabel(icon: icon, title: title, help: help).padding(.leading, 2) }
}

struct NumberBox: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var width: CGFloat = 64
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(size: 16, weight: .medium, design: .rounded).monospacedDigit())
            .frame(width: width, height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.field))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(focused ? Color.accentBlue : Color.fieldStroke, lineWidth: focused ? 2 : 1))
            .focused($focused)
            .onAppear { text = "\(value)" }
            .onChange(of: value) { _, v in if !focused { text = "\(v)" } }
            .onChange(of: focused) { _, f in if !f { commit() } }
            .onSubmit { commit() }
    }
    private func commit() {
        if let v = Int(text.filter(\.isNumber)) { value = min(max(v, range.lowerBound), range.upperBound) }
        text = "\(value)"
    }
}

struct SoftButtonStyle: ButtonStyle {
    var destructive = false
    var prominent = false
    var minWidth: CGFloat? = nil
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14.5, weight: .medium))
            .foregroundStyle(prominent ? Color.white : destructive ? Color.red : Color.primary)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .frame(minWidth: minWidth)
            .background(Capsule().fill(prominent ? Color.accentBlue : Color.soft))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

struct CircleButtonStyle: ButtonStyle {
    var tint: Color = .primary
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Color.soft))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Circle())
    }
}

struct Chip: View {
    let icon: String
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                Text(title).font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 15).padding(.vertical, 9)
            .background(Capsule().fill(selected ? Color.accentBlue : (hover ? Color.accentBlue.opacity(0.08) : .clear)))
            .overlay(Capsule().stroke(Color.accentBlue, lineWidth: 2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 10
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, w: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height); w = max(w, x - spacing)
        }
        return CGSize(width: proposal.width ?? w, height: y + rowH)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > b.width { x = 0; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: b.minX + x, y: b.minY + y), proposal: .unspecified)
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView(); v.material = material; v.blendingMode = .behindWindow; v.state = .followsWindowActiveState; return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

/// Horizontal battery drawing with fill level, limit marker and state symbol.
struct BatteryGlyph: View {
    var percent: Int
    var limit: Int? = nil
    var color: Color = .green
    var symbol: String? = nil
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let nubW = w * 0.045, bodyW = w - nubW - w * 0.015
            let r = h * 0.24, inset = h * 0.085
            HStack(spacing: w * 0.015) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: r, style: .continuous).stroke(Color.primary.opacity(0.22), lineWidth: max(2, h * 0.045))
                    RoundedRectangle(cornerRadius: r - inset, style: .continuous)
                        .fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .top, endPoint: .bottom))
                        .frame(width: max(h * 0.2, (bodyW - inset * 2) * CGFloat(min(max(percent, 0), 100)) / 100))
                        .padding(inset)
                    if let limit, limit < 100 {
                        Rectangle().fill(Color.primary.opacity(0.45))
                            .frame(width: 2, height: h * 0.62)
                            .offset(x: inset + (bodyW - inset * 2) * CGFloat(limit) / 100 - 1)
                    }
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: h * 0.42, weight: .bold))
                            .foregroundStyle(.white).shadow(color: .black.opacity(0.25), radius: 2)
                            .frame(width: bodyW)
                    }
                }
                .frame(width: bodyW)
                RoundedRectangle(cornerRadius: nubW / 2).fill(Color.primary.opacity(0.22)).frame(width: nubW, height: h * 0.36)
            }
        }
        .animation(.spring(duration: 0.6), value: percent)
    }
}

/// Little vertical battery used in the calibration flow.
struct MiniBattery: View {
    var fill: Double
    var color: Color
    var symbol: String
    var active = false
    var done = false
    var body: some View {
        ZStack {
            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.2)).frame(width: 12, height: 4)
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06))
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.opacity(0.75))
                        .frame(height: 44 * fill).padding(3)
                    Image(systemName: done ? "checkmark" : symbol).font(.system(size: 15, weight: .bold))
                        .frame(maxHeight: .infinity)
                }
                .frame(width: 30, height: 50)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(active ? Color.accentBlue : Color.primary.opacity(0.12), lineWidth: active ? 2.5 : 1))
            }
        }
        .scaleEffect(active ? 1.08 : 1)
    }
}
