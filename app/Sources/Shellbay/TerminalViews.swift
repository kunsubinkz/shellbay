import SwiftUI
import SwiftTerm
import ShellbayCore

private let ansiNormal = ["#3a3a3c", "#ff453a", "#30d158", "#ffd60a", "#0a84ff", "#bf5af2", "#64d2ff", "#d1d1d6"]
private let ansiBright = ["#8e8e93", "#ff6961", "#4ae37a", "#ffe066", "#409cff", "#da8fff", "#8ae2ff", "#ffffff"]

struct ResolvedTheme {
    var bg: String, fg: String, dim: String, red: String, green: String, blue: String, cursor: String
    init(_ t: TerminalTheme, dark: Bool, accent: String) {
        bg = t.bg ?? (dark ? "#141414" : "#ffffff"); fg = t.fg ?? (dark ? "#e4e4e4" : "#1d1d1f")
        dim = t.dim ?? (dark ? "#8a8a8e" : "#86868b"); red = t.red ?? (dark ? "#ff6b61" : "#d70015")
        green = t.green ?? (dark ? "#5ad87a" : "#248a3d"); blue = t.blue ?? (dark ? "#64a8ff" : "#0040dd")
        cursor = t.cursor ?? accent
    }
    var palette: [SwiftTerm.Color] {
        var n = ansiNormal, b = ansiBright
        n[0] = bg == "#141414" || bg == "#ffffff" ? n[0] : dim
        n[1] = red; b[1] = red; n[2] = green; b[2] = green; n[4] = blue; b[4] = blue
        n[7] = fg; b[0] = dim; b[7] = fg
        return (n + b).map { h in
            let c = hexToRGB(h)
            return SwiftTerm.Color(red: UInt16(c.r * 65535), green: UInt16(c.g * 65535), blue: UInt16(c.b * 65535))
        }
    }
}

struct TerminalPane: NSViewRepresentable {
    let session: TerminalSession
    let theme: TerminalTheme
    let fontSize: Double
    let cursor: CursorKind
    let focused: Bool
    @Environment(\.colorScheme) private var scheme

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let v = session.ensureView()
        if !session.launched { session.start() }
        return v
    }

    func updateNSView(_ v: LocalProcessTerminalView, context: Context) {
        let dark = scheme == .dark
        let t = ResolvedTheme(theme, dark: dark, accent: dark ? "#0a84ff" : "#007aff")
        v.installColors(t.palette)
        v.nativeBackgroundColor = NSColor(hex: t.bg)
        v.nativeForegroundColor = NSColor(hex: t.fg)
        v.caretColor = NSColor(hex: t.cursor)
        let f = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if v.font.pointSize != f.pointSize { v.font = f }
        let style: CursorStyle = switch cursor { case .block: .blinkBlock; case .bar: .blinkBar; case .underline: .blinkUnderline }
        v.getTerminal().setCursorStyle(style)
        if focused, let w = v.window, w.firstResponder !== v { w.makeFirstResponder(v) }
    }
}

struct WorkspaceTabBar: View {
    @Environment(AppStore.self) private var store
    @State private var picker = false
    var body: some View {
        let ws = store.workspace
        HStack(spacing: 0) {
            tabButton(selected: ws.activeTab == nil) {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2").font(.system(size: 10))
                    Text(homeLabel).lineLimit(1)
                }.frame(maxWidth: 150)
            } action: { ws.activeTab = nil }
            ForEach(ws.tabs) { t in
                tabButton(selected: ws.activeTab == t.id, width: 210) {
                    HStack(spacing: 6) {
                        Button { ws.close(tab: t) } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).frame(width: 16, height: 16)
                        }.buttonStyle(.plain).foregroundStyle(Tk.text3).help("Close Tab").accessibilityLabel("Close Tab")
                        Spacer(minLength: 0)
                        StatusDot(color: t.status.color)
                        Text(t.title).lineLimit(1)
                        if t.panes.count > 1 { Image(systemName: "square.split.2x1").font(.system(size: 10)).opacity(0.6) }
                        Spacer(minLength: 0)
                        Color.clear.frame(width: 16)
                    }
                } action: { ws.activeTab = t.id }
            }
            Button { picker = true } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).frame(width: 32, height: 30).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(Tk.text2).help("New Tab (⌘T)").accessibilityLabel("New Tab")
                .popover(isPresented: $picker, arrowEdge: .bottom) { HostPicker(isPresented: $picker) }
            Spacer(minLength: 0)
        }
        .frame(height: 30).background(Tk.tabbar)
        .overlay(alignment: .bottom) { Rectangle().fill(Tk.sep).frame(height: 0.5) }
        .onChange(of: store.newTabToken) { picker = true }
    }

    var homeLabel: String {
        switch store.selection {
        case .hosts: "Hosts"; case .group(let g): g; case .keychain: "Keychain"; case .snippets: "Snippets"
        case .sftp: "SFTP"; case .ports: "Port Forwarding"; case .settings: "Settings"
        }
    }

    func tabButton<C: View>(selected: Bool, width: CGFloat? = nil, @ViewBuilder _ content: () -> C, action: @escaping () -> Void) -> some View {
        content().font(.system(size: 12)).padding(.horizontal, 10)
            .frame(maxWidth: width ?? 150).frame(height: 30)
            .background(selected ? Tk.tabActive : .clear).foregroundStyle(selected ? Tk.text : Tk.text2)
            .overlay(alignment: .trailing) { Rectangle().fill(Tk.sep).frame(width: 0.5) }
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }
}

struct HostPicker: View {
    @Environment(AppStore.self) private var store
    @Binding var isPresented: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("New Session").font(.system(size: 11, weight: .semibold)).foregroundStyle(Tk.text3).padding(.horizontal, 8).padding(.top, 4)
            ForEach(store.hosts) { h in
                Button {
                    store.workspace.newTab(host: h); isPresented = false
                } label: {
                    HStack(spacing: 8) { StatusDot(color: h.status.color); Text(h.label); Spacer(); Text(h.address).font(Tk.mono(11)).foregroundStyle(Tk.text3) }
                        .padding(.horizontal, 8).frame(height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }.padding(8).frame(width: 300)
    }
}

struct TerminalWorkspaceView: View {
    @Environment(AppStore.self) private var store
    let tab: WorkspaceTab
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                PaneSplitView(tab: tab).opacity(tab.mode == .terminal ? 1 : 0).allowsHitTesting(tab.mode == .terminal)
                if tab.mode == .monitor { MonitorView(tab: tab) }
            }
            TerminalStatusBar(tab: tab)
        }
    }
}

struct PaneSplitView: View {
    @Environment(AppStore.self) private var store
    let tab: WorkspaceTab
    var body: some View {
        let layout = tab.axis == .horizontal ? AnyLayout(HStackLayout(spacing: 1)) : AnyLayout(VStackLayout(spacing: 1))
        layout {
            ForEach(tab.panes) { s in PaneView(tab: tab, session: s) }
        }.background(Tk.sep)
    }
}

struct PaneView: View {
    @Environment(AppStore.self) private var store
    let tab: WorkspaceTab
    let session: TerminalSession
    var focused: Bool { tab.focus == session.id }
    var body: some View {
        let multi = tab.panes.count > 1
        let theme = TerminalTheme.named(store.settings.theme)
        VStack(spacing: 0) {
            if multi {
                HStack(spacing: 6) {
                    StatusDot(color: session.status.color)
                    Text(session.userAtHost).font(Tk.mono(11)).foregroundStyle(Tk.text2).lineLimit(1)
                    Spacer()
                    Button { store.workspace.close(pane: session, in: tab) } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).frame(width: 16, height: 16)
                    }.buttonStyle(.plain).foregroundStyle(Tk.text3).help("Close Pane").accessibilityLabel("Close Pane")
                }.padding(.horizontal, 10).frame(height: 24).background(Tk.toolbar)
                    .overlay(alignment: .top) { Rectangle().fill(focused ? Tk.accent : .clear).frame(height: 2) }
            }
            ZStack {
                TerminalPane(session: session, theme: theme, fontSize: store.settings.fontSize, cursor: store.settings.cursor, focused: focused)
                    .id(session.attempt)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(termBackground(theme))
                if session.status == .connecting {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Connecting to \(session.host.hostname)…").font(Tk.mono(12)) }
                        .foregroundStyle(Tk.text2).padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .opacity(multi && !focused ? 0.6 : 1)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { tab.focus = session.id })
    }
    func termBackground(_ t: TerminalTheme) -> Color { t.bg.map { Color(hex: $0) } ?? Tk.term }
}

struct TerminalStatusBar: View {
    let tab: WorkspaceTab
    @Environment(AppStore.self) private var store
    var body: some View {
        if let s = tab.focused {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                HStack(spacing: 14) {
                    HStack(spacing: 6) { StatusDot(color: s.status.color); Text(s.status.label) }
                    Text(s.userAtHost).font(Tk.mono(11))
                    if let l = s.latency { Text(String(format: "%.0f ms", l)).monospacedDigit() }
                    if let c = s.connectedAt, s.status == .online { Text(Fmt.duration(ctx.date.timeIntervalSince(c))).font(Tk.mono(11)) }
                    Text("keep-alive \(store.settings.keepAlive > 0 ? "\(store.settings.keepAlive)s" : "off")")
                    Spacer()
                    if s.status == .failed || s.status == .closed {
                        Button("Reconnect") { s.reconnect() }.buttonStyle(PrimaryButtonStyle()).font(.system(size: 11))
                    }
                    Text(s.os)
                    Text("UTF-8").font(.system(size: 10, weight: .medium)).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Tk.field))
                }
                .font(.system(size: 11)).foregroundStyle(Tk.text2)
                .padding(.horizontal, 12).frame(height: 26).background(Tk.toolbar)
                .overlay(alignment: .top) { Rectangle().fill(Tk.sep).frame(height: 0.5) }
            }
        }
    }
}
