import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGPIPE, SIG_IGN)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct ShellbayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AppStore.shared

    var body: some Scene {
        WindowGroup("Shellbay") {
            RootView().environment(store)
                .task { if let d = ProcessInfo.processInfo.environment["SHELLBAY_SNAPSHOT"] { await Snapshotter.run(dir: d, store: store) } }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in store.workspace.closeAll() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1200, height: 780)
        .commands { ShellbayCommands(store: store) }
    }
}

struct ShellbayCommands: Commands {
    let store: AppStore
    var inTerminal: Bool { store.workspace.active != nil }
    var locked: Bool { store.locked }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Host") { store.sheet = .host(nil) }.keyboardShortcut("n", modifiers: .command).disabled(locked)
            Button("New Tab") { store.newTabToken += 1 }.keyboardShortcut("t", modifiers: .command).disabled(locked)
            Button("Close Tab") {
                if let t = store.workspace.active { store.workspace.close(tab: t) }
            }.keyboardShortcut("w", modifiers: .command).disabled(!inTerminal || locked)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { store.selection = .settings; store.workspace.activeTab = nil }.keyboardShortcut(",", modifiers: .command).disabled(locked)
        }
        CommandMenu("Host") {
            Button("Connect") { if let h = store.selectedHostValue { store.connect(h) } }.keyboardShortcut("o", modifiers: .command).disabled(store.selectedHostValue == nil || locked)
            Button("Edit…") { if let h = store.selectedHostValue { store.sheet = .host(h) } }.keyboardShortcut("e", modifiers: .command).disabled(store.selectedHostValue == nil || locked)
            if !inTerminal {
                Button("Duplicate") { if let h = store.selectedHostValue { store.duplicate(h) } }.keyboardShortcut("d", modifiers: .command).disabled(store.selectedHostValue == nil || locked)
            }
            Divider()
            Button("Delete…") { store.pendingDelete = store.selectedHostValue }.keyboardShortcut(.delete, modifiers: .command).disabled(store.selectedHostValue == nil || locked)
        }
        CommandMenu("Terminal") {
            Button("Show Terminal") { store.workspace.active?.mode = .terminal }.keyboardShortcut("1", modifiers: .command).disabled(!inTerminal || locked)
            Button("Show Monitor") { store.workspace.active?.mode = .monitor }.keyboardShortcut("2", modifiers: .command).disabled(!inTerminal || locked)
            Divider()
            if inTerminal { Button("Split Right") { store.workspace.split(.horizontal) }.keyboardShortcut("d", modifiers: .command).disabled(locked) }
            else { Button("Split Right") {}.disabled(true) }
            Button("Split Down") { store.workspace.split(.vertical) }.keyboardShortcut("d", modifiers: [.command, .shift]).disabled(!inTerminal || locked)
            Divider()
            Button("Lock Shellbay") { store.lock() }.keyboardShortcut("l", modifiers: [.command, .control])
        }
    }
}
