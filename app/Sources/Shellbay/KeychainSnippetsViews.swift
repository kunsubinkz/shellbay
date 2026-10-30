import SwiftUI
import ShellbayCore

struct KeychainView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SSH Keys").font(.system(size: 15, weight: .semibold))
                        Text("Stored in the macOS Keychain. Private keys never leave this Mac.").font(.system(size: 12)).foregroundStyle(Tk.text2)
                    }
                    Spacer()
                    Button { store.sheet = .importKey } label: { Label("Import Key…", systemImage: "square.and.arrow.down") }.buttonStyle(SecondaryButtonStyle())
                    Button { store.sheet = .generateKey } label: { Label("Generate Key", systemImage: "plus") }.buttonStyle(PrimaryButtonStyle())
                }
                if store.keys.isEmpty {
                    EmptyState(icon: "key", title: "No SSH Keys", message: "Generate a new key or import an existing one.").frame(minHeight: 280)
                } else {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Type").frame(width: 110, alignment: .leading)
                            Text("Fingerprint").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Created").frame(width: 100, alignment: .leading)
                            Color.clear.frame(width: 76)
                        }.font(.system(size: 11, weight: .semibold)).foregroundStyle(Tk.text3)
                            .padding(.horizontal, 14).frame(height: 26).background(Tk.card)
                            .overlay(alignment: .bottom) { Rectangle().fill(Tk.sep).frame(height: 0.5) }
                        ForEach(store.keys) { k in KeyRow(key: k) }
                    }.clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Tk.cardBorder, lineWidth: 0.5))
                }
            }.padding(.init(top: 20, leading: 24, bottom: 28, trailing: 24))
        }.background(Tk.win)
    }
}

struct KeyRow: View {
    @Environment(AppStore.self) private var store
    let key: SSHKeyMeta
    @State private var hover = false
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "key").foregroundStyle(Tk.accent).frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Tk.field))
                VStack(alignment: .leading, spacing: 1) {
                    Text(key.name).fontWeight(.semibold).lineLimit(1)
                    let n = store.usedBy(key)
                    Text(n == 0 ? "Not used by any host" : "Used by \(n) host\(n == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(Tk.text3)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(key.type).font(.system(size: 11, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 1)
                .background(Capsule().fill(Tk.field)).frame(width: 110, alignment: .leading)
            Text(key.shortFingerprint).font(Tk.mono(11.5)).foregroundStyle(Tk.text2).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(Fmt.shortDate(key.createdAt)).font(.system(size: 12)).foregroundStyle(Tk.text2).frame(width: 100, alignment: .leading)
            HStack(spacing: 2) {
                IconButton(symbol: "doc.on.doc", help: "Copy public key") { store.copyPublicKey(key) }
                IconButton(symbol: "trash", help: "Delete Key") { store.pendingKeyDelete = key }
            }.frame(width: 76, alignment: .trailing)
        }.padding(.horizontal, 14).padding(.vertical, 6).frame(minHeight: 48)
            .background(hover ? Tk.cardHover : .clear).onHover { hover = $0 }
            .overlay(alignment: .bottom) { Rectangle().fill(Tk.sep).frame(height: 0.5) }
    }
}

struct GenerateKeySheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type: KeyType = .ed25519
    @State private var error: String?
    @State private var submitted = false
    @State private var busy = false
    var body: some View {
        Sheet(width: 420) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Generate SSH Key").font(.system(size: 15, weight: .semibold))
                FormRow(label: "Name*") { ShellbayTextField(placeholder: "id_ed25519_work", text: $name, error: submitted ? error : nil, mono: true) }
                FormRow(label: "Type") {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("", selection: $type) { ForEach(KeyType.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
                        Text(type.hint).font(.system(size: 11)).foregroundStyle(Tk.text2)
                    }
                }
                HStack {
                    if busy { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Cancel") { dismiss() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                    Button("Generate") { generate() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction).disabled(busy)
                }
            }
        }.onChange(of: name) { if submitted { error = HostValidator.validateKeyName(name, existing: store.keys.map(\.name)) } }
    }
    func generate() {
        submitted = true
        error = HostValidator.validateKeyName(name, existing: store.keys.map(\.name))
        guard error == nil else { return }
        busy = true
        let n = name.trimmingCharacters(in: .whitespaces), t = type
        Task {
            do {
                let g = try await Task.detached { try KeyGenerator.generate(name: n, type: t) }.value
                try store.addKey(SSHKeyMeta(name: n, type: t.rawValue, fingerprint: g.fingerprint, publicKey: g.publicKey), privateKey: g.privateKey)
                store.showToast("Key “\(n)” generated"); dismiss()
            } catch { self.error = error.localizedDescription; busy = false }
        }
    }
}

struct ImportKeySheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var text = ""
    @State private var nameError: String?
    @State private var keyError: String?
    @State private var submitted = false
    var body: some View {
        Sheet(width: 480) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Import SSH Key").font(.system(size: 15, weight: .semibold))
                FormRow(label: "Name*") { ShellbayTextField(placeholder: "id_ed25519_old", text: $name, error: submitted ? nameError : nil, mono: true) }
                FormRow(label: "Private key*") {
                    VStack(alignment: .leading, spacing: 4) {
                        TextEditor(text: $text).font(Tk.mono(11)).scrollContentBackground(.hidden).padding(4).frame(height: 130)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Tk.field))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(submitted && keyError != nil ? Tk.bad : .clear, lineWidth: 1))
                        HStack {
                            Button("Choose File…") { chooseFile() }.buttonStyle(SecondaryButtonStyle()).font(.system(size: 11))
                            if submitted, let e = keyError { Text(e).font(.system(size: 11)).foregroundStyle(Tk.bad) }
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                    Button("Import") { doImport() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                }
            }
        }
        .onChange(of: name) { revalidate() }.onChange(of: text) { revalidate() }
    }
    func revalidate() {
        guard submitted else { return }
        nameError = HostValidator.validateKeyName(name, existing: store.keys.map(\.name)); keyError = HostValidator.validatePrivateKey(text)
    }
    func chooseFile() {
        let p = NSOpenPanel(); p.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        p.showsHiddenFiles = true; p.canChooseDirectories = false
        if p.runModal() == .OK, let u = p.url, let s = try? String(contentsOf: u, encoding: .utf8) {
            text = s; if name.isEmpty { name = u.lastPathComponent }
        }
    }
    func doImport() {
        submitted = true; revalidate()
        guard nameError == nil, keyError == nil else { return }
        do {
            let r = try KeyGenerator.importKey(privateKey: text)
            let n = name.trimmingCharacters(in: .whitespaces)
            try store.addKey(SSHKeyMeta(name: n, type: r.type.rawValue, fingerprint: r.fingerprint, publicKey: r.publicKey), privateKey: text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n")
            store.showToast("Key “\(n)” imported"); dismiss()
        } catch { keyError = "Could not read key (encrypted keys with a passphrase are not supported yet)." }
    }
}

// MARK: - Snippets

struct SnippetsView: View {
    @Environment(AppStore.self) private var store
    var rows: [Snippet] {
        let q = store.query.lowercased()
        return q.isEmpty ? store.snippets : store.snippets.filter { ([$0.name, $0.command] + $0.tags).contains { $0.lowercased().contains(q) } }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Snippets").font(.system(size: 15, weight: .semibold))
                        Text("Saved commands you can run on any host in one click.").font(.system(size: 12)).foregroundStyle(Tk.text2)
                    }
                    Spacer()
                    Button { store.sheet = .snippet(nil) } label: { Label("New Snippet", systemImage: "plus") }.buttonStyle(PrimaryButtonStyle())
                }
                if rows.isEmpty {
                    EmptyState(icon: nil, title: store.snippets.isEmpty ? "No Snippets" : "No Results",
                               message: store.snippets.isEmpty ? "Create a snippet to reuse your favourite commands." : "No snippets match “\(store.query)”.").frame(minHeight: 260)
                }
                ForEach(rows) { s in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "terminal").foregroundStyle(Tk.accent)
                            Text(s.name).fontWeight(.semibold).lineLimit(1)
                            ForEach(s.tags, id: \.self) { TagChip(text: $0) }
                            Spacer()
                            IconButton(symbol: "pencil", help: "Edit") { store.sheet = .snippet(s) }
                            IconButton(symbol: "trash", help: "Delete") { store.pendingSnippetDelete = s }
                            Button { store.sheet = .runSnippet(s) } label: { Label("Run", systemImage: "play.fill").labelStyle(.titleAndIcon) }.buttonStyle(SecondaryButtonStyle())
                        }
                        (Text("$ ").foregroundStyle(Tk.tDim) + Text(s.command)).font(Tk.mono(12)).textSelection(.enabled)
                            .padding(.horizontal, 10).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Tk.term)).foregroundStyle(Tk.termText)
                    }.padding(.horizontal, 14).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Tk.card))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Tk.cardBorder, lineWidth: 0.5))
                }
            }.padding(.init(top: 20, leading: 24, bottom: 28, trailing: 24))
        }.background(Tk.win)
    }
}

struct SnippetEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let editing: Snippet?
    @State private var name = ""
    @State private var command = ""
    @State private var tags = ""
    @State private var submitted = false
    var body: some View {
        Sheet(width: 460) {
            VStack(alignment: .leading, spacing: 14) {
                Text(editing == nil ? "New Snippet" : "Edit Snippet").font(.system(size: 15, weight: .semibold))
                FormRow(label: "Name*") { ShellbayTextField(placeholder: "Update system", text: $name, error: submitted && name.trimmingCharacters(in: .whitespaces).isEmpty ? "Name is required." : nil) }
                FormRow(label: "Command*") {
                    VStack(alignment: .leading, spacing: 3) {
                        TextEditor(text: $command).font(Tk.mono(12)).scrollContentBackground(.hidden).padding(4).frame(height: 90)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Tk.field))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(submitted && command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Tk.bad : .clear, lineWidth: 1))
                        if submitted && command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text("Command is required.").font(.system(size: 11)).foregroundStyle(Tk.bad) }
                    }
                }
                FormRow(label: "Tags") { ShellbayTextField(placeholder: "apt, maintenance", text: $tags) }
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                    Button("Save") { save() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                }
            }
        }.onAppear { if let e = editing { name = e.name; command = e.command; tags = e.tags.joined(separator: ", ") } }
    }
    func save() {
        submitted = true
        let n = name.trimmingCharacters(in: .whitespaces), c = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !c.isEmpty else { return }
        if let e = editing, let i = store.snippets.firstIndex(where: { $0.id == e.id }) {
            store.snippets[i].name = n; store.snippets[i].command = c; store.snippets[i].tags = parseTags(tags)
        } else { store.snippets.append(Snippet(name: n, command: c, tags: parseTags(tags))) }
        store.save(); dismiss()
    }
}

struct RunSnippetSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let snippet: Snippet
    @State private var hostID: UUID?
    var body: some View {
        Sheet(width: 440) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Run “\(snippet.name)”").font(.system(size: 15, weight: .semibold))
                (Text("$ ").foregroundStyle(Tk.tDim) + Text(snippet.command)).font(Tk.mono(12))
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 6).fill(Tk.term)).foregroundStyle(Tk.termText)
                Text("Run on").font(.system(size: 11, weight: .semibold)).foregroundStyle(Tk.text3)
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.hosts) { h in
                            let off = h.status == .offline
                            HStack(spacing: 8) {
                                StatusDot(color: h.status.color); Text(h.label); Spacer()
                                Text(h.address).font(Tk.mono(11)).foregroundStyle(Tk.text3)
                            }.padding(.horizontal, 8).frame(height: 28)
                                .background(RoundedRectangle(cornerRadius: 6).fill(hostID == h.id ? Tk.accent.opacity(0.25) : .clear))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(hostID == h.id ? Tk.accent : .clear, lineWidth: 1))
                                .opacity(off ? 0.4 : 1).contentShape(Rectangle())
                                .onTapGesture { if !off { hostID = h.id } }
                                .accessibilityLabel("\(h.label)\(off ? ", offline" : "")")
                        }
                    }
                }.frame(height: 180)
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                    Button { run() } label: { Label("Run", systemImage: "play.fill") }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction).disabled(hostID == nil)
                }
            }
        }
    }
    func run() {
        guard let h = store.hosts.first(where: { $0.id == hostID }) else { return }
        let tab = store.workspace.open(host: h)
        tab.mode = .terminal
        let cmd = snippet.command, timeout = Double(store.settings.timeout)
        if let s = tab.panes.first { Task { if !(await s.run(command: cmd, timeout: timeout)) { store.showToast("Could not run snippet: host not connected") } } }
        dismiss()
    }
}
