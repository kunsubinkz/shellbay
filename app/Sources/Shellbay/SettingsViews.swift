import SwiftUI
import ShellbayCore

enum Shortcuts {
    static let groups: [(String, [(String, String)])] = [
        ("General", [("New Host", "⌘N"), ("Search", "⌘F"), ("Settings", "⌘,"), ("Lock App", "⌃⌘L"), ("Close Menu or Dialog", "Esc")]),
        ("Hosts", [("Connect to Selected Host", "⌘O"), ("Edit Host", "⌘E"), ("Duplicate Host", "⌘D"), ("Delete Host", "⌘⌫")]),
        ("Terminal", [("New Tab", "⌘T"), ("Close Tab", "⌘W"), ("Show Terminal", "⌘1"), ("Show Monitor", "⌘2"), ("Split Right", "⌘D"), ("Split Down", "⇧⌘D"), ("Clear Screen", "⌃L"), ("Cancel Command", "⌃C"), ("Previous / Next Command", "↑ ↓")]),
    ]
}

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        @Bindable var s = store
        ScrollView {
            VStack(spacing: 20) {
                Picker("", selection: $s.settingsTab) {
                    ForEach(SettingsTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 360)
                Group {
                    switch store.settingsTab {
                    case .appearance: AppearanceSettings()
                    case .shortcuts: ShortcutSettings()
                    case .security: SecuritySettings()
                    case .connection: ConnectionSettings()
                    }
                }.frame(maxWidth: 680, alignment: .leading)
            }.frame(maxWidth: .infinity).padding(.init(top: 20, leading: 24, bottom: 32, trailing: 24))
        }.background(Tk.win)
    }
}

struct SettingsSection<C: View>: View {
    let title: String; @ViewBuilder var content: C
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 15, weight: .semibold))
            content
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppearanceSettings: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        @Bindable var s = store
        VStack(alignment: .leading, spacing: 22) {
            SettingsSection(title: "Terminal Theme") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(TerminalTheme.all) { t in
                        let r = ResolvedTheme(t, dark: scheme == .dark, accent: scheme == .dark ? "#0a84ff" : "#007aff")
                        let on = store.settings.theme == t.id
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 0) { Text("$ ").foregroundStyle(Color(hex: r.dim)); Text("ls").foregroundStyle(Color(hex: r.fg)) }
                            HStack(spacing: 6) {
                                Text("src/").foregroundStyle(Color(hex: r.blue)); Text("ok").foregroundStyle(Color(hex: r.green)); Text("err").foregroundStyle(Color(hex: r.red))
                            }
                            Spacer(minLength: 0)
                            Text(t.name).font(.system(size: 11, weight: .medium)).foregroundStyle(Color(hex: r.fg).opacity(0.8))
                        }.font(Tk.mono(10.5)).padding(10).frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: r.bg)))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? Tk.accent : Tk.cardBorder, lineWidth: on ? 2 : 0.5))
                            .overlay(alignment: .topTrailing) { if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(Tk.accent).padding(6) } }
                            .contentShape(Rectangle()).onTapGesture { store.settings.theme = t.id }
                            .accessibilityLabel("\(t.name) theme\(on ? ", selected" : "")").accessibilityAddTraits(.isButton)
                    }
                }
            }
            SettingsSection(title: "Font & Cursor") {
                HStack {
                    Text("Font size").frame(width: 90, alignment: .leading)
                    Slider(value: $s.settings.fontSize, in: 10...20, step: 1).frame(width: 240)
                    Text("\(Int(store.settings.fontSize)) pt").monospacedDigit().foregroundStyle(Tk.text2)
                }
                HStack {
                    Text("Cursor").frame(width: 90, alignment: .leading)
                    Picker("", selection: $s.settings.cursor) { ForEach(CursorKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 240)
                }
                HStack {
                    Text("Appearance").frame(width: 90, alignment: .leading)
                    Picker("", selection: $s.settings.appearance) { ForEach(AppearanceMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 240)
                }
            }
            SettingsSection(title: "Preview") {
                let r = ResolvedTheme(TerminalTheme.named(store.settings.theme), dark: scheme == .dark, accent: scheme == .dark ? "#0a84ff" : "#007aff")
                VStack(alignment: .leading, spacing: 2) {
                    (Text("ubuntu@web-prod-01").foregroundStyle(Color(hex: r.green)).bold() + Text(":").foregroundStyle(Color(hex: r.fg)) + Text("~").foregroundStyle(Color(hex: r.blue)).bold() + Text("$ ls -l").foregroundStyle(Color(hex: r.fg)))
                    Text("drwxr-xr-x  4 ubuntu ubuntu 4096 Oct 28 app").foregroundStyle(Color(hex: r.fg))
                    Text("-rwxr-xr-x  1 ubuntu ubuntu 2300 Oct 24 deploy.sh").foregroundStyle(Color(hex: r.fg))
                    HStack(spacing: 0) {
                        Text("ubuntu@web-prod-01").foregroundStyle(Color(hex: r.green)).bold(); Text(":~$ ").foregroundStyle(Color(hex: r.fg))
                        cursorShape(Color(hex: r.cursor))
                    }
                }.font(.system(size: store.settings.fontSize, design: .monospaced)).padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: r.bg)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Tk.cardBorder, lineWidth: 0.5))
            }
        }
    }
    @ViewBuilder func cursorShape(_ c: Color) -> some View {
        let sz = store.settings.fontSize
        switch store.settings.cursor {
        case .block: Rectangle().fill(c).frame(width: sz * 0.6, height: sz * 1.25)
        case .bar: Rectangle().fill(c).frame(width: 2, height: sz * 1.25)
        case .underline: Rectangle().fill(c).frame(width: sz * 0.6, height: 2).offset(y: sz * 0.5)
        }
    }
}

struct ShortcutSettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(Shortcuts.groups, id: \.0) { title, items in
                SettingsSection(title: title) {
                    VStack(spacing: 0) {
                        ForEach(items, id: \.0) { label, keys in
                            HStack {
                                Text(label); Spacer()
                                HStack(spacing: 4) {
                                    ForEach(Array((keys.contains(" ") || keys == "Esc" ? keys.split(separator: " ").map(String.init) : keys.map(String.init)).enumerated()), id: \.offset) { Keycap(key: $0.element) }
                                }
                            }.padding(.horizontal, 12).frame(height: 32).overlay(alignment: .bottom) { Rectangle().fill(Tk.sep).frame(height: 0.5) }
                        }
                    }.background(RoundedRectangle(cornerRadius: 8).fill(Tk.card))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Tk.cardBorder, lineWidth: 0.5))
                }
            }
        }
    }
}

struct SecuritySettings: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        @Bindable var s = store
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(title: "App Lock") {
                Toggle("Require PIN to open Shellbay", isOn: Binding(
                    get: { store.settings.pinOn },
                    set: { on in store.sheet = on ? .setPin : .disablePin }
                )).toggleStyle(.switch)
                HStack {
                    Text("Auto-lock after")
                    Picker("", selection: $s.settings.lockMin) {
                        ForEach([1, 2, 5, 10, 15, 30], id: \.self) { Text("\($0) minute\($0 == 1 ? "" : "s")").tag($0) }
                    }.labelsHidden().frame(width: 140).disabled(!store.settings.pinOn)
                }
                HStack {
                    Button("Change PIN…") { store.sheet = .changePin }.buttonStyle(SecondaryButtonStyle()).disabled(!store.settings.pinOn)
                    Button { store.lock() } label: { Label("Lock Now  ⌃⌘L", systemImage: "lock") }.buttonStyle(SecondaryButtonStyle()).disabled(!store.settings.pinOn)
                }
                Text("The PIN is stored as a salted PBKDF2 hash in the macOS Keychain.").font(.system(size: 11)).foregroundStyle(Tk.text3)
            }
        }
    }
}

struct ConnectionSettings: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        @Bindable var s = store
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(title: "Connection") {
                HStack {
                    Text("Keep-alive interval").frame(width: 150, alignment: .leading)
                    Picker("", selection: $s.settings.keepAlive) {
                        Text("Off").tag(0); ForEach([15, 30, 60, 120], id: \.self) { Text("\($0) s").tag($0) }
                    }.labelsHidden().frame(width: 120)
                }
                HStack {
                    Text("Connection timeout").frame(width: 150, alignment: .leading)
                    Picker("", selection: $s.settings.timeout) { ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) s").tag($0) } }.labelsHidden().frame(width: 120)
                }
                Text("Equivalent ssh_config").font(.system(size: 11, weight: .semibold)).foregroundStyle(Tk.text3).padding(.top, 6)
                Text("Host *\n    ServerAliveInterval \(store.settings.keepAlive)\n    ConnectTimeout \(store.settings.timeout)")
                    .font(Tk.mono(12)).textSelection(.enabled).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Tk.term)).foregroundStyle(Tk.termText)
            }
        }
    }
}

// MARK: - PIN sheet & lock screen

struct PinSheet: View {
    enum Mode { case set, disable, change }
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    @State private var current = ""
    @State private var pin1 = ""
    @State private var pin2 = ""
    @State private var error: String?
    var title: String { switch mode { case .set: "Set PIN"; case .disable: "Turn Off PIN"; case .change: "Change PIN" } }
    var body: some View {
        Sheet(width: 340) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.system(size: 15, weight: .semibold))
                if mode != .set { field("Current PIN", $current) }
                if mode != .disable { field("New PIN (4 digits)", $pin1); field("Confirm PIN", $pin2) }
                if let error { Text(error).font(.system(size: 11)).foregroundStyle(Tk.bad) }
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                    Button(mode == .disable ? "Turn Off" : "Save") { commit() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                }
            }
        }
    }
    func field(_ label: String, _ b: Binding<String>) -> some View {
        SecureField(label, text: Binding(get: { b.wrappedValue }, set: { b.wrappedValue = String($0.filter(\.isNumber).prefix(4)) }))
            .textFieldStyle(.plain).padding(.horizontal, 8).frame(height: 24).background(RoundedRectangle(cornerRadius: 6).fill(Tk.field))
    }
    func commit() {
        if mode != .set, !store.pins.verify(current) { error = "Incorrect PIN. Try again."; return }
        if mode == .disable { store.pins.clear(); store.settings.pinOn = false; dismiss(); return }
        guard PinStore.isValidPin(pin1) else { error = "PIN must be exactly 4 digits."; return }
        guard pin1 == pin2 else { error = "PINs do not match."; return }
        do { try store.pins.setPin(pin1); store.settings.pinOn = true; store.touch(); store.showToast(mode == .set ? "PIN enabled" : "PIN changed"); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct LockScreenView: View {
    @Environment(AppStore.self) private var store
    @State private var pin = ""
    @State private var wrong = false
    @State private var shake: CGFloat = 0
    @FocusState private var focused: Bool
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "lock.fill").font(.system(size: 28)).foregroundStyle(Tk.text2)
                    .frame(width: 64, height: 64).background(RoundedRectangle(cornerRadius: 16).fill(Tk.field))
                Text("Shellbay is Locked").font(.system(size: 17, weight: .semibold))
                HStack(spacing: 14) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle().fill(i < pin.count ? Tk.text : .clear).overlay(Circle().strokeBorder(Tk.text2, lineWidth: 1)).frame(width: 11, height: 11)
                    }
                }.offset(x: shake).padding(.top, 6)
                Text(wrong ? "Incorrect PIN. Try again." : "Enter your PIN").font(.system(size: 12)).foregroundStyle(wrong ? Tk.bad : Tk.text2)
                TextField("", text: Binding(get: { pin }, set: { v in pin = String(v.filter(\.isNumber).prefix(4)); if pin.count == 4 { submit() } else { wrong = false } }))
                    .focused($focused).textFieldStyle(.plain).frame(width: 1, height: 1).opacity(0.01)
                    .accessibilityLabel("PIN")
            }
        }
        .onAppear { focused = true }
        .onTapGesture { focused = true }
    }
    func submit() {
        if store.pins.verify(pin) { store.locked = false; store.touch(); pin = ""; wrong = false }
        else {
            wrong = true; pin = ""
            withAnimation(.easeInOut(duration: 0.06).repeatCount(5, autoreverses: true)) { shake = 10 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { shake = 0 }
        }
    }
}
