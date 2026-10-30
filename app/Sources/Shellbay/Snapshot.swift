import AppKit
import SwiftUI
import ShellbayCore

/// Dev-only: with SHELLBAY_SNAPSHOT=<dir> the app renders its own window for each major screen to PNG, then quits.
/// Uses the window's own view hierarchy, so no Screen Recording permission is required.
@MainActor
enum Snapshotter {
    static func run(dir: String, store: AppStore) async {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? await Task.sleep(for: .seconds(2))
        func snap(_ name: String) async {
            try? await Task.sleep(for: .milliseconds(900))
            for (i, w) in NSApp.windows.enumerated() where w.isVisible {
                guard let v = w.contentView?.superview ?? w.contentView else { continue }
                guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
                v.cacheDisplay(in: v.bounds, to: rep)
                if let d = rep.representation(using: .png, properties: [:]) { try? d.write(to: URL(fileURLWithPath: "\(dir)/\(name)\(i == 0 ? "" : "-w\(i)").png")) }
            }
        }
        func dump(_ v: NSView, _ d: Int, _ out: inout String) {
            let n = String(describing: type(of: v))
            if n.contains("Outline") || n.contains("TableView") || n.contains("Sidebar") || n.contains("SplitView") { out += String(repeating: " ", count: d) + n + " \(v.frame)" + ((v as? NSTableView).map { " rows=\($0.numberOfRows)" } ?? "") + "\n" }
            v.subviews.forEach { dump($0, d + 1, &out) }
        }
        var o = ""; NSApp.windows.first.flatMap { $0.contentView?.superview }.map { dump($0, 0, &o) }
        try? o.write(toFile: "\(dir)/viewtree.txt", atomically: true, encoding: .utf8)
        store.settings.appearance = .dark
        store.selection = .hosts; store.gridMode = true; await snap("01-hosts-grid-dark")
        store.selectedHost = store.hosts[0].id; await snap("02-hosts-selected")
        store.gridMode = false; await snap("03-hosts-list")
        store.gridMode = true
        store.sheet = .host(nil); await snap("04-host-editor")
        store.sheet = .host(store.hosts[0]); await snap("04b-host-edit-existing")
        store.sheet = nil
        store.query = "postgres"; await snap("05-search"); store.query = "zzzz"; await snap("05b-search-empty"); store.query = ""
        store.selection = .keychain; await snap("06-keychain")
        store.sheet = .generateKey; await snap("07-generate-key"); store.sheet = nil
        store.selection = .snippets; await snap("08-snippets")
        store.sheet = .runSnippet(store.snippets[0]); await snap("08b-run-snippet"); store.sheet = nil
        store.selection = .sftp; await snap("09-sftp"); try? await Task.sleep(for: .seconds(3)); await snap("09b-sftp-after")
        for t in SettingsTab.allCases { store.selection = .settings; store.settingsTab = t; await snap("10-settings-\(t.rawValue.lowercased())") }
        store.settings.theme = "dracula"; store.settingsTab = .appearance; await snap("10b-settings-dracula"); store.settings.theme = "default"
        store.selection = .ports; await snap("11-ports")
        store.selection = .hosts
        var e2eHost: Host?
        if let kp = ProcessInfo.processInfo.environment["SB_E2E_KEY"], let pk = try? String(contentsOfFile: kp, encoding: .utf8),
           let r = try? KeyGenerator.importKey(privateKey: pk) {
            try? store.addKey(SSHKeyMeta(name: "e2e_key", type: r.type.rawValue, fingerprint: r.fingerprint, publicKey: r.publicKey), privateKey: pk)
            let h = Host(label: "docker-ubuntu", hostname: "127.0.0.1", port: 2222, username: "ubuntu", authMethod: .key, keyRef: "e2e_key", group: "Personal", tags: ["docker", "e2e"], colorHex: "#30d158", osHint: "Ubuntu 24.04 LTS")
            store.upsert(h, password: nil); e2eHost = h
            try? await Task.sleep(for: .seconds(2)); await snap("11b-hosts-with-online")
            store.selection = .sftp; store.sftpPick = h.id; await snap("11c-sftp-e2e"); try? await Task.sleep(for: .seconds(4)); await snap("11d-sftp-e2e-loaded")
            // queue UI: one real upload (slow-ish, so progress is visible) + one that fails (permission denied)
            let big = FileManager.default.temporaryDirectory.appendingPathComponent("sb-snap-upload.bin")
            try? Data(count: 40 * 1024 * 1024).write(to: big)
            let a = store.makeAuth(for: h), t = a.target
            for (name, dest) in [("sb-snap-upload.bin", "/home/ubuntu/app"), ("sb-snap-upload.bin", "/root")] {
                let job = TransferJob(name: name, route: "\(big.path) → \(h.label):\(dest)", isUpload: true) { token, progress in
                    try await Task.detached { try Transfer.upload(local: big, remoteDir: dest, target: t, token: token, progress: progress) }.value
                }
                store.transfers.enqueue(job)
            }
            try? await Task.sleep(for: .milliseconds(400)); await snap("11e-transfers-running"); try? await Task.sleep(for: .seconds(4)); await snap("11f-transfers-done")
            store.selection = .hosts
        }
        if let h = e2eHost ?? store.hosts.first { store.connect(h) }
        await snap("12-terminal-connecting"); try? await Task.sleep(for: .seconds(3))
        store.workspace.active?.focused?.send("ls -la --color=auto; echo; uname -a; printf '\\033[31mred\\033[32m green\\033[34m blue\\033[0m\\n'\n")
        await snap("12b-terminal-later")
        store.workspace.active?.mode = .monitor; await snap("13-monitor"); try? await Task.sleep(for: .seconds(7)); await snap("13b-monitor-later")
        store.workspace.active?.mode = .terminal
        store.workspace.split(.horizontal); await snap("14-split")
        store.settings.appearance = .light; await snap("15-terminal-light")
        store.workspace.activeTab = nil; store.selection = .hosts; await snap("16-hosts-light")
        store.settings.appearance = .dark
        store.pins.clear(); try? store.pins.setPin("1234"); store.settings.pinOn = true; store.locked = true; await snap("17-lock")
        store.locked = false; store.pins.clear(); store.settings.pinOn = false
        store.workspace.closeAll(); store.keys.first(where: { $0.name == "e2e_key" }).map { store.deleteKey($0) }
        NSApp.terminate(nil)
    }
}
