import SwiftUI
import AppKit
import ShellbayCore

struct SidebarView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        @Bindable var s = store
        List(selection: Binding(get: { store.selection }, set: { if let v = $0 { store.selection = v; store.workspace.activeTab = nil } })) {
            Section("Favorites") {
                row("Hosts", "server.rack", .hosts, badge: store.hosts.count)
                row("Keychain", "key", .keychain)
                row("Snippets", "terminal", .snippets)
                row("SFTP", "folder.badge.gearshape", .sftp)
                row("Port Forwarding", "arrow.left.arrow.right", .ports)
            }
            Section("Groups") {
                ForEach(store.groups, id: \.self) { g in row(g, "folder", .group(g), badge: store.count(in: g)) }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                Button { store.selection = .settings; store.workspace.activeTab = nil } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape").foregroundStyle(Tk.accent).frame(width: 16)
                        Text("Settings"); Spacer(); Text("⌘,").font(.system(size: 11)).foregroundStyle(Tk.text3)
                    }.padding(.horizontal, 8).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 6).fill(store.selection == .settings ? Tk.sel : .clear))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).padding(10)
            }
        }
    }
    func row(_ title: String, _ icon: String, _ item: SidebarItem, badge: Int? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(Tk.accent).frame(width: 16)
            Text(title)
            Spacer()
            if let badge { Text("\(badge)").font(.system(size: 11)).foregroundStyle(Tk.text3) }
        }.tag(item).frame(height: 20)
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var s = store
        ZStack {
            NavigationSplitView {
                SidebarView().navigationSplitViewColumnWidth(224)
            } detail: {
                DetailView()
                    .navigationTitle(title).navigationSubtitle(subtitle)
                    .toolbar { toolbarContent }
                    .searchable(text: $s.query, placement: .toolbar, prompt: "Search")
            }
            .toolbarBackground(Tk.toolbar, for: .windowToolbar)
            .blur(radius: store.locked ? 40 : 0)
            .disabled(store.locked)
            if store.locked { LockScreenView().transition(.opacity) }
        }
        .frame(minWidth: 900, minHeight: 560)
        .preferredColorScheme(store.settings.appearance == .system ? nil : (store.settings.appearance == .dark ? .dark : .light))
        .sheet(item: $s.sheet) { sheet in
            switch sheet {
            case .host(let h): HostEditorSheet(editing: h)
            case .generateKey: GenerateKeySheet()
            case .importKey: ImportKeySheet()
            case .snippet(let sn): SnippetEditorSheet(editing: sn)
            case .runSnippet(let sn): RunSnippetSheet(snippet: sn)
            case .setPin: PinSheet(mode: .set)
            case .disablePin: PinSheet(mode: .disable)
            case .changePin: PinSheet(mode: .change)
            }
        }
        .confirmationDialog("Delete “\(store.pendingDelete?.label ?? "")”?", isPresented: Binding(get: { store.pendingDelete != nil }, set: { if !$0 { store.pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let h = store.pendingDelete { store.delete(h) }; store.pendingDelete = nil }
            Button("Cancel", role: .cancel) { store.pendingDelete = nil }
        } message: { Text("This host will be removed. This can’t be undone.") }
        .confirmationDialog("Delete key “\(store.pendingKeyDelete?.name ?? "")”?", isPresented: Binding(get: { store.pendingKeyDelete != nil }, set: { if !$0 { store.pendingKeyDelete = nil } }), titleVisibility: .visible) {
            Button("Delete Key", role: .destructive) { if let k = store.pendingKeyDelete { store.deleteKey(k) }; store.pendingKeyDelete = nil }
            Button("Cancel", role: .cancel) { store.pendingKeyDelete = nil }
        } message: {
            let n = store.pendingKeyDelete.map { store.usedBy($0) } ?? 0
            Text(n > 0 ? "\(n) host\(n == 1 ? " uses" : "s use") this key and will show “Key missing”. This can’t be undone." : "The private key will be removed from the Keychain. This can’t be undone.")
        }
        .confirmationDialog("Delete snippet “\(store.pendingSnippetDelete?.name ?? "")”?", isPresented: Binding(get: { store.pendingSnippetDelete != nil }, set: { if !$0 { store.pendingSnippetDelete = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let sn = store.pendingSnippetDelete { store.snippets.removeAll { $0.id == sn.id }; store.save() }; store.pendingSnippetDelete = nil }
            Button("Cancel", role: .cancel) { store.pendingSnippetDelete = nil }
        }
        .overlay(alignment: .bottom) {
            if let t = store.toast { ToastView(text: t).padding(.bottom, 44).transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .animation(.easeOut(duration: 0.2), value: store.toast)
        .animation(.easeOut(duration: 0.15), value: store.locked)
        .onAppear { store.startProbing(); startIdleMonitor() }
    }

    var title: String {
        if let t = store.workspace.active { return t.focused?.userAtHost ?? t.title }
        switch store.selection {
        case .hosts: return "Hosts"; case .group(let g): return g; case .keychain: return "Keychain"; case .snippets: return "Snippets"
        case .sftp: return "SFTP"; case .ports: return "Port Forwarding"; case .settings: return "Settings"
        }
    }
    var subtitle: String {
        if let t = store.workspace.active, let s = t.focused { return "\(s.host.username)@\(s.host.hostname)" }
        switch store.selection {
        case .hosts: return "\(store.visibleHosts.count) hosts"
        case .group: return "\(store.visibleHosts.count) hosts"
        case .keychain: return "\(store.keys.count) keys"
        case .snippets: return "\(store.snippets.count) snippets"
        default: return ""
        }
    }

    @ToolbarContentBuilder var toolbarContent: some ToolbarContent {
        @Bindable var s = store
        ToolbarItemGroup(placement: .navigation) {
            if let t = store.workspace.active {
                @Bindable var tab = t
                Picker("", selection: $tab.mode) {
                    Label("Terminal", systemImage: "terminal").tag(WorkspaceMode.terminal)
                    Label("Monitor", systemImage: "waveform.path.ecg").tag(WorkspaceMode.monitor)
                }.pickerStyle(.segmented).help("Terminal (⌘1) / Monitor (⌘2)")
                Button { store.workspace.split(.horizontal) } label: { Image(systemName: "square.split.2x1") }
                    .help("Split Right (⌘D)").disabled(t.panes.count >= 4)
                Button { store.workspace.split(.vertical) } label: { Image(systemName: "square.split.1x2") }
                    .help("Split Down (⇧⌘D)").disabled(t.panes.count >= 4)
            } else if store.selection == .hosts || { if case .group = store.selection { return true }; return false }() {
                Picker("", selection: $s.gridMode) {
                    Image(systemName: "square.grid.2x2").tag(true).help("Icon view")
                    Image(systemName: "list.bullet").tag(false).help("List view")
                }.pickerStyle(.segmented)
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                s.settings.appearance = (s.settings.appearance == .dark) ? .light : .dark
            } label: { Image(systemName: "circle.lefthalf.filled") }.help("Toggle appearance")
            Button { store.sheet = .host(nil) } label: { Image(systemName: "plus") }.help("New Host (⌘N)")
        }
    }

    @State private var monitor: Any?
    @State private var timer: Timer?
    func startIdleMonitor() {
        guard monitor == nil else { return }
        let st = store
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .mouseMoved, .scrollWheel]) { e in
            Task { @MainActor in st.touch() }
            return e
        }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in Task { @MainActor in st.checkIdle() } }
        let nc = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            nc.addObserver(forName: n, object: nil, queue: .main) { _ in Task { @MainActor in if st.settings.pinOn && st.pins.isSet { st.locked = true } } }
        }
    }
}

struct DetailView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        VStack(spacing: 0) {
            if !store.workspace.tabs.isEmpty { WorkspaceTabBar() }
            if let t = store.workspace.active { TerminalWorkspaceView(tab: t).id(t.id) }
            else {
                switch store.selection {
                case .hosts, .group: HostsView()
                case .keychain: KeychainView()
                case .snippets: SnippetsView()
                case .sftp: SFTPView()
                case .ports: EmptyState(icon: "arrow.left.arrow.right", title: "Port Forwarding", message: "Create local, remote and dynamic tunnels that start with a connection.\nComing soon.").background(Tk.win)
                case .settings: SettingsView()
                }
            }
        }.background(Tk.win)
    }
}
