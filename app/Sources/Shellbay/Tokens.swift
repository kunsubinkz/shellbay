import SwiftUI
import AppKit
import ShellbayCore

typealias Host = ShellbayCore.Host
typealias Color = SwiftUI.Color

extension NSColor {
    convenience init(hex: String, alpha: CGFloat = 1) {
        let c = hexToRGB(hex); self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha)
    }
    static func dyn(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { ap in ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }
}
extension Color {
    init(hex: String, alpha: Double = 1) { self.init(nsColor: NSColor(hex: hex, alpha: alpha)) }
    static func dyn(_ dark: NSColor, _ light: NSColor) -> Color { Color(nsColor: .dyn(dark: dark, light: light)) }
}

private func w(_ a: CGFloat) -> NSColor { NSColor(white: 1, alpha: a) }
private func k(_ a: CGFloat) -> NSColor { NSColor(white: 0, alpha: a) }

/// Design tokens (README "Design Tokens"), dark / light.
enum Tk {
    static let accent = Color.dyn(NSColor(hex: "#0a84ff"), NSColor(hex: "#007aff"))
    static let ok = Color.dyn(NSColor(hex: "#30d158"), NSColor(hex: "#28b44a"))
    static let warn = Color.dyn(NSColor(hex: "#ffd60a"), NSColor(hex: "#e6b800"))
    static let bad = Color.dyn(NSColor(hex: "#ff453a"), NSColor(hex: "#ff3b30"))
    static let win = Color.dyn(NSColor(hex: "#1e1e1e"), NSColor(hex: "#ffffff"))
    static let toolbar = Color.dyn(NSColor(hex: "#262626"), NSColor(hex: "#f6f6f6"))
    static let tabbar = Color.dyn(NSColor(hex: "#171717"), NSColor(hex: "#e8e8ea"))
    static let tabActive = Color.dyn(NSColor(hex: "#1e1e1e"), NSColor(hex: "#f6f6f6"))
    static let text = Color.dyn(w(0.88), k(0.86))
    static let text2 = Color.dyn(w(0.56), k(0.55))
    static let text3 = Color.dyn(w(0.32), k(0.35))
    static let sep = Color.dyn(w(0.08), k(0.08))
    static let hover = Color.dyn(w(0.07), k(0.05))
    static let sel = Color.dyn(w(0.11), k(0.08))
    static let card = Color.dyn(w(0.04), NSColor(hex: "#fafafa"))
    static let cardHover = Color.dyn(w(0.07), NSColor(hex: "#f3f3f4"))
    static let cardBorder = Color.dyn(w(0.07), k(0.08))
    static let cardSel = Color.dyn(NSColor(hex: "#0a84ff", alpha: 0.16), NSColor(hex: "#007aff", alpha: 0.09))
    static let field = Color.dyn(w(0.08), k(0.055))
    static let sheet = Color.dyn(NSColor(hex: "#2b2b2d"), NSColor(hex: "#f2f2f4"))
    static let btn = Color.dyn(w(0.12), NSColor.white)
    static let term = Color.dyn(NSColor(hex: "#141414"), NSColor(hex: "#ffffff"))
    static let termText = Color.dyn(NSColor(hex: "#e4e4e4"), NSColor(hex: "#1d1d1f"))
    static let tDim = Color.dyn(NSColor(hex: "#8a8a8e"), NSColor(hex: "#86868b"))
    static let tRed = Color.dyn(NSColor(hex: "#ff6b61"), NSColor(hex: "#d70015"))
    static let tGreen = Color.dyn(NSColor(hex: "#5ad87a"), NSColor(hex: "#248a3d"))
    static let tBlue = Color.dyn(NSColor(hex: "#64a8ff"), NSColor(hex: "#0040dd"))
    static let purple = Color(hex: "#bf5af2")
    static let ubuntu = Color(hex: "#E95420")
    static let sidebarTint = Color.dyn(NSColor(red: 40/255, green: 40/255, blue: 42/255, alpha: 0.62), NSColor(red: 234/255, green: 234/255, blue: 237/255, alpha: 0.68))

    static let mono: (CGFloat) -> Font = { .system(size: $0, design: .monospaced) }
}

// MARK: - Components

struct StatusDot: View {
    var color: Color; var size: CGFloat = 7
    var body: some View { Circle().fill(color).frame(width: size, height: size) }
}

extension HostStatus {
    var color: Color { switch self { case .online: return Tk.ok; case .connecting: return Tk.warn; case .offline: return Tk.bad } }
    var label: String { switch self { case .online: return "Online"; case .connecting: return "Connecting…"; case .offline: return "Offline" } }
}

struct TagChip: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10.5)).padding(.horizontal, 7).padding(.vertical, 1)
            .background(Capsule().fill(Tk.field)).foregroundStyle(Tk.text2)
    }
}

struct Keycap: View {
    let key: String
    var body: some View {
        Text(key).font(.system(size: 12, weight: .medium)).foregroundStyle(Tk.text)
            .frame(minWidth: 22, minHeight: 22).padding(.horizontal, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Tk.btn))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Tk.cardBorder, lineWidth: 0.5))
    }
}

struct UbuntuLogo: View {
    var size: CGFloat = 32
    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 32
            ctx.fill(Path(ellipseIn: CGRect(x: 0, y: 0, width: 32 * s, height: 32 * s)), with: .color(Tk.ubuntu))
            ctx.stroke(Path(ellipseIn: CGRect(x: 9 * s, y: 9 * s, width: 14 * s, height: 14 * s)), with: .color(.white), lineWidth: 2.4 * s)
            for (x, y) in [(9.0, 16.0), (19.5, 9.94), (19.5, 22.06)] {
                let r = CGRect(x: (x - 2.7) * s, y: (y - 2.7) * s, width: 5.4 * s, height: 5.4 * s)
                ctx.fill(Path(ellipseIn: r), with: .color(.white))
                ctx.stroke(Path(ellipseIn: r), with: .color(Tk.ubuntu), lineWidth: 1.3 * s)
            }
        }.frame(width: size, height: size)
    }
}

struct EmptyState: View {
    let icon: String?; let title: String; let message: String
    var body: some View {
        VStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 28)).foregroundStyle(Tk.text3) }
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tk.text)
            Text(message).foregroundStyle(Tk.text2).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
    }
}

struct ToastView: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Tk.ok)
            Text(text).font(.system(size: 13)).foregroundStyle(Tk.text)
        }.padding(.horizontal, 14).padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Tk.cardBorder, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }
}

struct ColorSwatchPicker: View {
    @Binding var hex: String
    var body: some View {
        HStack(spacing: 8) {
            ForEach(colorChoices, id: \.hex) { c in
                Button { hex = c.hex } label: {
                    Circle().fill(Color(hex: c.hex)).frame(width: 16, height: 16)
                        .padding(2.5).overlay(Circle().strokeBorder(hex == c.hex ? Color(hex: c.hex) : .clear, lineWidth: 1.5))
                }.buttonStyle(.plain).help(c.name).accessibilityLabel(c.name)
            }
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13)).padding(.horizontal, 12).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(destructive ? Tk.bad : Tk.accent))
            .foregroundStyle(.white).opacity(configuration.isPressed ? 0.8 : 1)
    }
}
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13)).padding(.horizontal, 12).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(Tk.btn))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Tk.cardBorder, lineWidth: 0.5))
            .foregroundStyle(Tk.text).opacity(configuration.isPressed ? 0.7 : 1)
    }
}
struct IconButton: View {
    let symbol: String; var help: String = ""; var tint: Color = Tk.text2; let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(hover ? Tk.text : tint)
                .frame(width: 28, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Tk.hover : .clear))
        }.buttonStyle(.plain).onHover { hover = $0 }.help(help).accessibilityLabel(help)
    }
}

struct Sheet<Content: View>: View {
    let width: CGFloat; @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).frame(width: width).background(Tk.sheet)
    }
}

struct ShellbayTextField: View {
    let placeholder: String; @Binding var text: String; var error: String? = nil; var mono = false
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(mono ? Tk.mono(12) : .system(size: 13))
                .padding(.horizontal, 8).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Tk.field))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(error == nil ? .clear : Tk.bad, lineWidth: 1)
                    .padding(-1).background(RoundedRectangle(cornerRadius: 7).strokeBorder((error == nil ? Color.clear : Tk.bad.opacity(0.3)), lineWidth: 2).padding(-2)))
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(Tk.bad) }
        }
    }
}

struct FormRow<Content: View>: View {
    let label: String; @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label).foregroundStyle(Tk.text2).frame(width: 110, alignment: .trailing).frame(minHeight: 24)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
