import SwiftUI
import Observation
import Network
import ShellbayCore
import AppKit

enum SidebarItem: Hashable { case hosts, group(String), keychain, snippets, sftp, ports, settings }
enum AppearanceMode: String, Codable, CaseIterable { case system = "System", dark = "Dark", light = "Light" }
enum CursorKind: String, Codable, CaseIterable { case block = "Block", bar = "Bar", underline = "Underline" }
enum SettingsTab: String, CaseIterable { case appearance = "Appearance", shortcuts = "Shortcuts", security = "Security", connection = "Connection" }

struct AppSettings: Codable, Equatable {
    var theme = "default"; var fontSize = 13.0; var cursor: CursorKind = .block
    var pinOn = false; var lockMin = 5; var keepAlive = 30; var timeout = 15
    var appearance: AppearanceMode = .dark
}

struct PersistedData: Codable { var hosts: [Host]; var keys: [SSHKeyMeta]; var snippets: [Snippet] }

enum Sheets: Identifiable {
    case host(Host?), generateKey, importKey, snippet(Snippet?), runSnippet(Snippet), setPin, disablePin, changePin
    var id: String {
        switch self {
        case .host(let h): return "host-\(h?.id.uuidString ?? "new")"
        case .generateKey: return "genkey"; case .importKey: return "impkey"
        case .snippet(let s): return "snip-\(s?.id.uuidString ?? "new")"
        case .runSnippet(let s): return "run-\(s.id)"
        case .setPin: return "setpin"; case .disablePin: return "disablepin"; case .changePin: return "changepin"
        }
    }
}

@Observable @MainActor
final class AppStore {
    var hosts: [Host] = []
    var keys: [SSHKeyMeta] = []
    var snippets: [Snippet] = []
    var settings = AppSettings() { didSet { saveSettings() } }

    var selection: SidebarItem = .hosts
    var gridMode = true
    var query = ""
    var selectedHost: UUID?
    var sheet: Sheets?
    var toast: String?
    var settingsTab: SettingsTab = .appearance
    var locked = false
    var searchFocusToken = 0
    var pendingDelete: Host?
    var newTabToken = 0
    var sftpPick: UUID?
    var pendingKeyDelete: SSHKeyMeta?
    var pendingSnippetDelete: Snippet?

    static let shared = AppStore(dataURL: ProcessInfo.processInfo.environment["SHELLBAY_DATA"].map { URL(fileURLWithPath: $0) })
    let secrets: SecretStore
    let pins: PinStore
    let workspace = Workspace()
    let transfers = TransferCenter()
    private let dataURL: URL
    private var toastTask: Task<Void, Never>?
    private var probeTask: Task<Void, Never>?
    var lastActivity = Date()

    init(secrets: SecretStore = KeychainStore(), dataURL: URL? = nil) {
        self.secrets = secrets
        self.pins = PinStore(store: secrets)
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Shellbay")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.dataURL = dataURL ?? dir.appendingPathComponent("data.json")
        load()
        workspace.store = self
        if settings.pinOn && pins.isSet { locked = true }
    }

    // MARK: persistence
    private func load() {
        if let d = try? Data(contentsOf: dataURL), let p = try? JSONDecoder().decode(PersistedData.self, from: d) {
            hosts = p.hosts; keys = p.keys; snippets = p.snippets
        } else {
            hosts = Seed.hosts; keys = Seed.keys; snippets = Seed.snippets
            save()
        }
        if let d = UserDefaults.standard.data(forKey: "shellbay.settings"), let s = try? JSONDecoder().decode(AppSettings.self, from: d) { settings = s }
    }
    func save() {
        let p = PersistedData(hosts: hosts, keys: keys, snippets: snippets)
        if let d = try? JSONEncoder().encode(p) { try? d.write(to: dataURL, options: .atomic) }
    }
    private func saveSettings() {
        if let d = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(d, forKey: "shellbay.settings") }
    }

    // MARK: toast
    func showToast(_ t: String) {
        toast = t; toastTask?.cancel()
        toastTask = Task { try? await Task.sleep(for: .seconds(2)); if !Task.isCancelled { toast = nil } }
    }

    // MARK: hosts
    var groups: [String] { var g = defaultGroups; for h in hosts where !g.contains(h.group) { g.append(h.group) }; return g }
    func count(in group: String) -> Int { hosts.filter { $0.group == group }.count }

    func matches(_ h: Host, _ q: String) -> Bool {
        let q = q.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return true }
        return ([h.label, h.hostname, h.username, h.group, h.osHint] + h.tags).contains { $0.lowercased().contains(q) }
    }
    var visibleHosts: [Host] {
        hosts.filter { h in
            if case .group(let g) = selection, h.group != g { return false }
            return matches(h, query)
        }
    }
    var selectedHostValue: Host? { hosts.first { $0.id == selectedHost } }

    func upsert(_ host: Host, password: String?) {
        if let i = hosts.firstIndex(where: { $0.id == host.id }) { hosts[i] = host } else { hosts.append(host) }
        if host.authMethod == .password, let password, !password.isEmpty {
            try? secrets.set(password, service: SecretService.host(host.id), account: host.username)
        }
        if host.authMethod == .key { secrets.delete(service: SecretService.host(host.id), account: host.username) }
        save()
    }
    func duplicate(_ h: Host) {
        var c = h; c.id = UUID(); c.label = HostValidator.duplicateLabel(of: h.label, existing: hosts.map(\.label)); c.createdAt = Date()
        if let pw = secrets.get(service: SecretService.host(h.id), account: h.username) { try? secrets.set(pw, service: SecretService.host(c.id), account: c.username) }
        hosts.append(c); selectedHost = c.id; save(); showToast("Duplicated \(h.label)")
    }
    func delete(_ h: Host) {
        hosts.removeAll { $0.id == h.id }
        secrets.delete(service: SecretService.host(h.id), account: h.username)
        if selectedHost == h.id { selectedHost = nil }
        save()
    }
    func connect(_ h: Host) { workspace.open(host: h); selection = .hosts }

    // MARK: keys
    func usedBy(_ key: SSHKeyMeta) -> Int { hosts.filter { $0.keyRef == key.name }.count }
    func keyMissing(_ h: Host) -> Bool { h.authMethod == .key && h.keyRef != nil && !keys.contains { $0.name == h.keyRef } }
    func privateKey(named n: String) -> String? { secrets.get(service: SecretService.key, account: n) }
    func addKey(_ meta: SSHKeyMeta, privateKey: String) throws {
        try secrets.set(privateKey, service: SecretService.key, account: meta.name)
        keys.append(meta); save()
    }
    func deleteKey(_ k: SSHKeyMeta) {
        secrets.delete(service: SecretService.key, account: k.name)
        keys.removeAll { $0.name == k.name }; save()
    }
    func copyPublicKey(_ k: SSHKeyMeta) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(k.publicKey, forType: .string)
        showToast("Đã copy public key")
    }

    // MARK: ssh targets
    struct Auth { var target: SSHTarget; var env: [String: String]; var cleanup: () -> Void }
    /// Builds a non-interactive ssh target for exec/SFTP. Key from Keychain → temp identity file; password → SSH_ASKPASS.
    func makeAuth(for h: Host, batch: Bool = true) -> Auth {
        var t = SSHTarget(host: h.hostname, user: h.username, port: h.port, timeout: settings.timeout, keepAlive: settings.keepAlive)
        var env: [String: String] = [:]
        var cleanup: () -> Void = {}
        if h.authMethod == .key, let name = h.keyRef, let pk = privateKey(named: name), let f = TempKeyFile(privateKey: pk) {
            t.identityFile = f.path; cleanup = { f.cleanup() }
        } else if h.authMethod == .password, let pw = secrets.get(service: SecretService.host(h.id), account: h.username) {
            env = ["SSH_ASKPASS": AskPass.scriptPath, "SSH_ASKPASS_REQUIRE": "force", "SB_PW": pw, "DISPLAY": "shellbay"]
            t.password = true; t.env = env
        }
        return Auth(target: t, env: env, cleanup: cleanup)
    }

    // MARK: reachability probes
    func startProbing() {
        probeTask?.cancel()
        probeTask = Task {
            while !Task.isCancelled {
                await withTaskGroup(of: (UUID, Double?).self) { g in
                    for h in hosts { g.addTask { (h.id, await Probe.rtt(host: h.hostname, port: h.port, timeout: 2)) } }
                    for await (id, rtt) in g {
                        if let i = hosts.firstIndex(where: { $0.id == id }) { hosts[i].status = rtt == nil ? .offline : .online }
                    }
                }
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    // MARK: lock
    func lock() { guard settings.pinOn, pins.isSet else { showToast("Enable a PIN in Settings → Security first"); return }; locked = true }
    func touch() { lastActivity = Date() }
    func checkIdle() {
        guard settings.pinOn, pins.isSet, !locked else { return }
        if Date().timeIntervalSince(lastActivity) > Double(settings.lockMin) * 60 { locked = true }
    }
}

enum AskPass {
    static var scriptPath: String {
        let p = FileManager.default.temporaryDirectory.appendingPathComponent("shellbay-askpass.sh").path
        if !FileManager.default.fileExists(atPath: p) {
            FileManager.default.createFile(atPath: p, contents: Data("#!/bin/sh\nprintf '%s\\n' \"$SB_PW\"\n".utf8), attributes: [.posixPermissions: 0o700])
        }
        return p
    }
}

enum Probe {
    /// TCP connect RTT in ms, nil if unreachable within timeout.
    static func rtt(host: String, port: Int, timeout: Double) async -> Double? {
        guard let p = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return nil }
        return await withCheckedContinuation { cont in
            let c = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tcp)
            let start = Date()
            let box = OnceBox(cont)
            c.stateUpdateHandler = { s in
                switch s {
                case .ready: box.resume(Date().timeIntervalSince(start) * 1000); c.cancel()
                case .failed, .cancelled: box.resume(nil)
                default: break
                }
            }
            c.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { box.resume(nil); c.cancel() }
        }
    }
}
final class OnceBox: @unchecked Sendable {
    private var cont: CheckedContinuation<Double?, Never>?; private let lock = NSLock()
    init(_ c: CheckedContinuation<Double?, Never>) { cont = c }
    func resume(_ v: Double?) { lock.lock(); let c = cont; cont = nil; lock.unlock(); c?.resume(returning: v) }
}
