import SwiftUI
import Observation
import SwiftTerm
import ShellbayCore

enum SessionStatus { case connecting, online, failed, closed
    var label: String { switch self { case .connecting: "Connecting…"; case .online: "Connected"; case .failed: "Connection failed"; case .closed: "Disconnected" } }
    var color: Color { switch self { case .connecting: Tk.warn; case .online: Tk.ok; case .failed: Tk.bad; case .closed: Tk.text3 } }
}

final class PTYDelegate: LocalProcessTerminalViewDelegate {
    weak var session: TerminalSession?
    init(_ s: TerminalSession) { session = s }
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak session] in session?.processExited(code: exitCode) }
    }
}

@Observable @MainActor
final class TerminalSession: Identifiable {
    let id = UUID()
    let host: Host
    var status: SessionStatus = .connecting
    var connectedAt: Date?
    var latency: Double?
    var os: String
    var attempt = 0
    @ObservationIgnored var termView: LocalProcessTerminalView?
    @ObservationIgnored private var delegate: PTYDelegate?
    @ObservationIgnored private var auth: AppStore.Auth?
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored weak var store: AppStore?
    @ObservationIgnored var launched = false

    init(host: Host, store: AppStore) { self.host = host; self.store = store; self.os = host.osHint }

    var userAtHost: String { "\(host.username)@\(host.label)" }

    func ensureView() -> LocalProcessTerminalView {
        if let v = termView { return v }
        let v = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let d = PTYDelegate(self); delegate = d; v.processDelegate = d
        termView = v
        return v
    }

    func start() {
        guard let store, !launched else { return }
        launched = true; attempt += 1
        status = .connecting
        let v = ensureView()
        let a = store.makeAuth(for: host)
        auth = a
        var args = ["-o", "ConnectTimeout=\(store.settings.timeout)", "-o", "StrictHostKeyChecking=accept-new", "-p", String(host.port)]
        if store.settings.keepAlive > 0 { args += ["-o", "ServerAliveInterval=\(store.settings.keepAlive)"] }
        if let f = a.target.identityFile { args += ["-i", f, "-o", "IdentitiesOnly=yes"] }
        args.append("\(host.username)@\(host.hostname)")
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("LANG=en_US.UTF-8")
        v.startProcess(executable: "/usr/bin/ssh", args: args, environment: env)
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in await self?.pingLoop() }
    }

    private func pingLoop() async {
        let h = host
        var firstProbe = true
        while !Task.isCancelled {
            let rtt = await Probe.rtt(host: h.hostname, port: h.port, timeout: 3)
            if Task.isCancelled { return }
            if let rtt {
                latency = rtt
                if status == .connecting { status = .online; connectedAt = Date(); detectOS() }
            } else {
                latency = nil
                if firstProbe && status == .connecting {
                    status = .failed
                    termView?.feed(text: "\r\n\u{1b}[31mConnection failed: cannot reach \(h.hostname):\(h.port) (connection refused or timed out).\u{1b}[0m\r\n")
                    termView?.terminate()
                }
            }
            firstProbe = false
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func detectOS() {
        guard let store else { return }
        let a = store.makeAuth(for: host)
        let t = a.target
        Task { [weak self] in
            defer { a.cleanup() }
            if let out = try? await SSHRunner.exec(t, "grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"'"), !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self?.os = out.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    func processExited(code: Int32?) {
        status = (code == 0) ? .closed : .failed
        if status == .closed { latency = nil }
        monitorTask?.cancel()
        auth?.cleanup(); auth = nil
        launched = false
    }

    func reconnect() {
        termView?.terminate()
        let old = termView; termView = nil; _ = old
        delegate = nil
        launched = false
        connectedAt = nil
        needsNewView += 1
        start()
    }
    var needsNewView = 0

    func send(_ text: String) { termView?.send(data: ArraySlice(Array(text.utf8))) }

    func close() {
        monitorTask?.cancel()
        termView?.terminate()
        auth?.cleanup(); auth = nil
    }

    /// Waits for the session to be online, then types a command into the PTY.
    func run(command: String, timeout: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while status == .connecting && Date() < deadline { try? await Task.sleep(for: .milliseconds(200)) }
        guard status == .online else { return false }
        try? await Task.sleep(for: .milliseconds(1500))   // let the login banner / prompt appear
        send(command + "\n")
        return true
    }
}

enum WorkspaceMode { case terminal, monitor }

@Observable @MainActor
final class WorkspaceTab: Identifiable {
    let id = UUID()
    var panes: [TerminalSession]
    var axis: Axis = .horizontal
    var focus: UUID
    var mode: WorkspaceMode = .terminal
    let monitor = MonitorModel()
    init(first: TerminalSession) { panes = [first]; focus = first.id }
    var title: String { panes.first?.host.label ?? "Session" }
    var focused: TerminalSession? { panes.first { $0.id == focus } ?? panes.first }
    var status: SessionStatus { focused?.status ?? .closed }
}

@Observable @MainActor
final class Workspace {
    var tabs: [WorkspaceTab] = []
    var activeTab: UUID?          // nil = home
    weak var store: AppStore?

    var active: WorkspaceTab? { tabs.first { $0.id == activeTab } }

    @discardableResult
    func open(host: Host) -> WorkspaceTab {
        if let t = tabs.first(where: { $0.panes.contains { $0.host.id == host.id } }) { activeTab = t.id; return t }
        return newTab(host: host)
    }
    @discardableResult
    func newTab(host: Host) -> WorkspaceTab {
        guard let store else { fatalError("store not set") }
        let s = TerminalSession(host: host, store: store)
        let t = WorkspaceTab(first: s); tabs.append(t); activeTab = t.id
        if let i = store.hosts.firstIndex(where: { $0.id == host.id }) { _ = i }
        return t
    }
    func close(tab: WorkspaceTab) {
        tab.monitor.stop(); tab.panes.forEach { $0.close() }
        tabs.removeAll { $0.id == tab.id }
        if activeTab == tab.id { activeTab = tabs.last?.id }
    }
    func split(_ axis: Axis) {
        guard let t = active, let f = t.focused, let store, t.panes.count < 4 else { return }
        if t.panes.count == 1 { t.axis = axis }
        let s = TerminalSession(host: f.host, store: store)
        t.panes.append(s); t.focus = s.id
    }
    func close(pane: TerminalSession, in tab: WorkspaceTab) {
        pane.close(); tab.panes.removeAll { $0.id == pane.id }
        if tab.panes.isEmpty { close(tab: tab) } else if tab.focus == pane.id { tab.focus = tab.panes[0].id }
    }
    func closeAll() { tabs.forEach { $0.monitor.stop(); $0.panes.forEach { $0.close() } } }
}

// MARK: - Monitor

struct MonitorPoint: Identifiable { let id = UUID(); var t: Date; var cpu: Double; var mem: Double }

@Observable @MainActor
final class MonitorModel {
    var points: [MonitorPoint] = []
    var cpu = 0.0
    var mem: MemInfo?
    var disk: DiskInfo?
    var uptime = 0.0
    var procs: [ProcRow] = []
    var error: String?
    var running = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var prev: CPUTimes?

    func start(store: AppStore, host: Host) {
        guard task == nil else { return }
        running = true; error = nil
        task = Task { [weak self] in
            let a = store.makeAuth(for: host)
            defer { a.cleanup() }
            while !Task.isCancelled {
                do {
                    let out = try await SSHRunner.exec(a.target, ProcParsers.metricsCommand)
                    guard let r = ProcParsers.parseCombined(out) else { throw SSHError.failed("Unsupported remote system (needs Linux /proc)") }
                    self?.apply(r)
                } catch {
                    self?.error = (error as? SSHError).flatMap { if case .failed(let m) = $0 { return m } else { return nil } } ?? error.localizedDescription
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    private func apply(_ r: (cpu: CPUTimes, mem: MemInfo, uptime: TimeInterval, disk: DiskInfo?, procs: [ProcRow])) {
        error = nil
        if let p = prev { cpu = ProcParsers.cpuPercent(prev: p, cur: r.cpu) }
        prev = r.cpu; mem = r.mem; disk = r.disk; uptime = r.uptime; procs = r.procs
        points.append(MonitorPoint(t: Date(), cpu: cpu, mem: r.mem.percent))
        if points.count > 60 { points.removeFirst(points.count - 60) }
    }
    func stop() { task?.cancel(); task = nil; running = false; prev = nil }
}

// MARK: - Transfers

enum TransferState { case queued, running, done, failed(String), cancelled }

@Observable @MainActor
final class TransferJob: Identifiable {
    let id = UUID()
    let name: String
    let route: String
    let isUpload: Bool
    var state: TransferState = .queued
    var done: Int64 = 0
    var total: Int64 = 1
    var speed = Double(0)
    var eta: Double?
    let token = CancelToken()
    let run: @Sendable (CancelToken, @escaping @Sendable (TransferProgress) -> Void) async throws -> Void
    var onFinish: (() -> Void)?
    var cleanup: () -> Void = {}
    init(name: String, route: String, isUpload: Bool, run: @escaping @Sendable (CancelToken, @escaping @Sendable (TransferProgress) -> Void) async throws -> Void) {
        self.name = name; self.route = route; self.isUpload = isUpload; self.run = run
    }
    var pct: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }
    var isActive: Bool { if case .running = state { return true }; return false }
    var isQueued: Bool { if case .queued = state { return true }; return false }
    var isFinished: Bool { switch state { case .done, .failed, .cancelled: return true; default: return false } }
    var isDone: Bool { if case .done = state { return true }; return false }
}

@Observable @MainActor
final class TransferCenter {
    var jobs: [TransferJob] = []
    let maxParallel = 2
    var onCompleted: ((TransferJob) -> Void)?

    func enqueue(_ job: TransferJob) { jobs.append(job); pump() }
    func cancel(_ j: TransferJob) {
        j.token.cancel()
        if j.isQueued { j.state = .cancelled; j.cleanup() }
    }
    func clearCompleted() { jobs.removeAll { $0.isFinished } }

    var summary: String {
        let a = jobs.filter(\.isActive).count, q = jobs.filter(\.isQueued).count, c = jobs.filter(\.isFinished).count
        return "\(a) active · \(q) queued · \(c) completed"
    }

    private func pump() {
        while jobs.filter(\.isActive).count < maxParallel, let j = jobs.first(where: \.isQueued) {
            j.state = .running
            var meter = SpeedMeter()
            let start = Date()
            let box = ProgressBox()
            Task {
                do {
                    try await j.run(j.token) { p in box.set(p) }
                    j.done = j.total; j.state = .done
                } catch {
                    if j.token.isCancelled { j.state = .cancelled }
                    else {
                        let m = (error as? SSHError).flatMap { if case .failed(let m) = $0 { return m } else { return nil } } ?? error.localizedDescription
                        j.state = .failed(m.localizedCaseInsensitiveContains("permission denied") ? "Permission denied" : m)
                    }
                }
                j.cleanup(); onCompleted?(j); pump()
            }
            Task {
                while j.isActive {
                    let p = box.get()
                    j.total = max(p.total, 1); j.done = p.done
                    meter.update(done: p.done, now: Date().timeIntervalSince(start))
                    j.speed = meter.bytesPerSec; j.eta = meter.eta(remaining: p.total - p.done)
                    try? await Task.sleep(for: .milliseconds(150))
                }
            }
        }
    }
}

final class ProgressBox: @unchecked Sendable {
    private var p = TransferProgress(done: 0, total: 1); private let l = NSLock()
    func set(_ v: TransferProgress) { l.lock(); p = v; l.unlock() }
    func get() -> TransferProgress { l.lock(); defer { l.unlock() }; return p }
}
