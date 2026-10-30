import SwiftUI
import ShellbayCore

struct HostsView: View {
    @Environment(AppStore.self) private var store

    private var grouped: [(String, [Host])] {
        store.groups.compactMap { g in
            let hs = store.visibleHosts.filter { $0.group == g }
            return hs.isEmpty ? nil : (g, hs)
        }
    }

    var body: some View {
        let groups = grouped
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if groups.isEmpty {
                    if store.hosts.isEmpty {
                        EmptyState(icon: "server.rack", title: "No Hosts", message: "Add a host with the + button or ⌘N.").frame(minHeight: 300)
                    } else {
                        EmptyState(icon: nil, title: "No Results", message: "No hosts match “\(store.query)”.").frame(minHeight: 300)
                    }
                }
                ForEach(groups, id: \.0) { name, hosts in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 7) {
                            Image(systemName: "folder").foregroundStyle(Tk.accent).font(.system(size: 13))
                            Text(name).font(.system(size: 13, weight: .semibold))
                            Text("\(hosts.count)").font(.system(size: 12)).foregroundStyle(Tk.text3)
                        }
                        if store.gridMode {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 232), spacing: 10, alignment: .top)], spacing: 10) {
                                ForEach(hosts) { h in HostCard(host: h) }
                            }
                        } else {
                            VStack(spacing: 0) {
                                ForEach(hosts) { h in HostRow(host: h) }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Tk.cardBorder, lineWidth: 0.5))
                        }
                    }
                }
                if !groups.isEmpty {
                    Text("Double-click a host to connect · Right-click for more options")
                        .font(.system(size: 11)).foregroundStyle(Tk.text3).frame(maxWidth: .infinity)
                }
            }.padding(.init(top: 20, leading: 24, bottom: 28, trailing: 24))
        }
        .contentShape(Rectangle())
        .onTapGesture { store.selectedHost = nil }
        .background(Tk.win)
        .onKeyPress(.return) {
            if let h = store.selectedHostValue { store.connect(h); return .handled }
            return .ignored
        }
    }
}

struct HostContextMenu: View {
    @Environment(AppStore.self) private var store
    let host: Host
    var body: some View {
        Button("Connect") { store.connect(host) }.keyboardShortcut("o", modifiers: .command)
        Button("Edit…") { store.sheet = .host(host) }.keyboardShortcut("e", modifiers: .command)
        Button("Duplicate") { store.duplicate(host) }.keyboardShortcut("d", modifiers: .command)
        Divider()
        Button("Delete", role: .destructive) { store.pendingDelete = host }.keyboardShortcut(.delete, modifiers: .command)
    }
}

struct HostCard: View {
    @Environment(AppStore.self) private var store
    let host: Host
    @State private var hover = false
    var selected: Bool { store.selectedHost == host.id }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                UbuntuLogo(size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(host.label).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        RoundedRectangle(cornerRadius: 2).fill(Color(hex: host.colorHex)).frame(width: 8, height: 8).help("Color")
                        if store.keyMissing(host) {
                            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(Tk.warn).help("Key missing")
                        }
                    }
                    Text(host.address).font(Tk.mono(11.5)).foregroundStyle(Tk.text2).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if !host.tags.isEmpty {
                HStack(spacing: 4) { ForEach(host.tags, id: \.self) { TagChip(text: $0) } }.padding(.top, -4)
            }
            HStack(spacing: 6) {
                StatusDot(color: host.status.color)
                Text(host.status.label)
                Spacer()
                Text(host.osHint).foregroundStyle(Tk.text3)
            }.font(.system(size: 11)).foregroundStyle(Tk.text2)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Tk.cardSel : (hover ? Tk.cardHover : Tk.card)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Tk.cardBorder, lineWidth: 0.5))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Tk.accent : .clear, lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { store.selectedHost = host.id; store.connect(host) }
        .onTapGesture { store.selectedHost = host.id }
        .contextMenu { HostContextMenu(host: host).onAppear { store.selectedHost = host.id } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(host.label), \(host.address), \(host.status.label)")
        .accessibilityAddTraits(.isButton)
    }
}

struct HostRow: View {
    @Environment(AppStore.self) private var store
    let host: Host
    @State private var hover = false
    var selected: Bool { store.selectedHost == host.id }
    var body: some View {
        HStack(spacing: 12) {
            UbuntuLogo(size: 20).frame(width: 22)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: host.colorHex)).frame(width: 8, height: 8)
                Text(host.label).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1.2)
            Text(host.address).font(Tk.mono(11.5)).foregroundStyle(Tk.text2).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(host.osHint).font(.system(size: 12)).foregroundStyle(Tk.text3).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) { StatusDot(color: host.status.color); Text(host.status.label) }
                .font(.system(size: 12)).foregroundStyle(Tk.text2).frame(width: 110, alignment: .leading)
        }
        .padding(.horizontal, 14).frame(height: 36)
        .background(selected ? Tk.cardSel : (hover ? Tk.cardHover : .clear))
        .overlay(alignment: .bottom) { Rectangle().fill(Tk.sep).frame(height: 0.5) }
        .overlay { if selected { Rectangle().strokeBorder(Tk.accent, lineWidth: 1.5) } }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { store.selectedHost = host.id; store.connect(host) }
        .onTapGesture { store.selectedHost = host.id }
        .contextMenu { HostContextMenu(host: host).onAppear { store.selectedHost = host.id } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(host.label), \(host.address), \(host.status.label)")
    }
}

// MARK: - Editor

struct HostEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let editing: Host?
    @State private var f = HostFormInput()
    @State private var group = "Personal"
    @State private var tags = ""
    @State private var color = "#0a84ff"
    @State private var submitted = false
    @State private var errors: [HostField: String] = [:]

    var existingLabels: [String] { store.hosts.filter { $0.id != editing?.id }.map(\.label) }

    var body: some View {
        Sheet(width: 500) {
            VStack(alignment: .leading, spacing: 14) {
                Text(editing == nil ? "New Host" : "Edit Host").font(.system(size: 15, weight: .semibold))
                VStack(alignment: .leading, spacing: 10) {
                    FormRow(label: "Label*") { ShellbayTextField(placeholder: "e.g. web-prod-01", text: $f.label, error: shown(.label)) }
                    FormRow(label: "Hostname/IP*") {
                        HStack(alignment: .top, spacing: 8) {
                            ShellbayTextField(placeholder: "10.0.1.11 or example.com", text: $f.hostname, error: shown(.hostname), mono: true)
                            HStack(spacing: 6) {
                                Text("Port").foregroundStyle(Tk.text2)
                                ShellbayTextField(placeholder: "22", text: $f.port, error: shown(.port), mono: true).frame(width: 64)
                            }
                        }
                    }
                    FormRow(label: "Username*") { ShellbayTextField(placeholder: "ubuntu", text: $f.username, error: shown(.username)) }
                    FormRow(label: "Authentication") {
                        VStack(alignment: .leading, spacing: 6) {
                            Picker("", selection: $f.authMethod) {
                                ForEach(AuthMethod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }.pickerStyle(.segmented).labelsHidden().frame(width: 220)
                            if f.authMethod == .key {
                                Picker("", selection: Binding(get: { f.keyRef ?? "" }, set: { f.keyRef = $0 })) {
                                    Text("Choose a key…").tag("")
                                    ForEach(store.keys) { Text($0.name).tag($0.name) }
                                }.labelsHidden()
                                if let k = store.keys.first(where: { $0.name == f.keyRef }) {
                                    Text("\(k.shortFingerprint) · created \(Fmt.shortDate(k.createdAt))").font(Tk.mono(11)).foregroundStyle(Tk.text3)
                                }
                                if let e = shown(.key) { Text(e).font(.system(size: 11)).foregroundStyle(Tk.bad) }
                            } else {
                                VStack(alignment: .leading, spacing: 3) {
                                    SecureField("Password", text: $f.password).textFieldStyle(.plain)
                                        .padding(.horizontal, 8).frame(height: 24)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(Tk.field))
                                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(shown(.password) == nil ? .clear : Tk.bad, lineWidth: 1))
                                    if let e = shown(.password) { Text(e).font(.system(size: 11)).foregroundStyle(Tk.bad) }
                                }
                            }
                        }
                    }
                    FormRow(label: "Group") {
                        Picker("", selection: $group) { ForEach(store.groups, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 180)
                    }
                    FormRow(label: "Tags") {
                        VStack(alignment: .leading, spacing: 6) {
                            ShellbayTextField(placeholder: "nginx, docker (max 6)", text: $tags)
                            let t = parseTags(tags)
                            if !t.isEmpty { HStack(spacing: 4) { ForEach(t, id: \.self) { TagChip(text: $0) } } }
                        }
                    }
                    FormRow(label: "Color") { ColorSwatchPicker(hex: $color).frame(minHeight: 24) }
                }
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                    Button("Save") { save() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: f.label) { revalidate() }
        .onChange(of: f.hostname) { revalidate() }
        .onChange(of: f.port) { revalidate() }
        .onChange(of: f.username) { revalidate() }
        .onChange(of: f.password) { revalidate() }
        .onChange(of: f.authMethod) { revalidate() }
        .onChange(of: f.keyRef) { revalidate() }
    }

    private func shown(_ k: HostField) -> String? { submitted ? errors[k] : nil }
    private func revalidate() { if submitted { errors = HostValidator.validate(f, existingLabels: existingLabels) } }

    private func load() {
        guard let h = editing else { f.keyRef = store.keys.first?.name; return }
        f.label = h.label; f.hostname = h.hostname; f.port = String(h.port); f.username = h.username
        f.authMethod = h.authMethod; f.keyRef = h.keyRef; group = h.group; tags = h.tags.joined(separator: ", "); color = h.colorHex
        f.password = store.secrets.get(service: SecretService.host(h.id), account: h.username) ?? ""
    }

    private func save() {
        submitted = true
        errors = HostValidator.validate(f, existingLabels: existingLabels)
        guard errors.isEmpty else { return }
        var h = editing ?? Host(label: "", hostname: "", username: "")
        h.label = f.label.trimmingCharacters(in: .whitespaces); h.hostname = f.hostname.trimmingCharacters(in: .whitespaces)
        h.port = Int(f.port.trimmingCharacters(in: .whitespaces)) ?? 22; h.username = f.username.trimmingCharacters(in: .whitespaces)
        h.authMethod = f.authMethod; h.keyRef = f.authMethod == .key ? f.keyRef : nil
        h.group = group; h.tags = parseTags(tags); h.colorHex = color
        if editing == nil { h.status = .connecting }
        if let old = editing, old.username != h.username { store.secrets.delete(service: SecretService.host(old.id), account: old.username) }
        store.upsert(h, password: f.authMethod == .password ? f.password : nil)
        store.selectedHost = h.id
        dismiss()
    }
}
