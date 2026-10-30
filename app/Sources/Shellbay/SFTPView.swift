import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable
import ShellbayCore

enum PaneSide: String, Codable { case local, remote }

struct DragItem: Codable, Transferable {
    var side: PaneSide; var path: String; var name: String; var isDir: Bool
    static var transferRepresentation: some TransferRepresentation { CodableRepresentation(contentType: .json) }
}

@Observable @MainActor
final class BrowserModel {
    let side: PaneSide
    var path: [String]
    var entries: [FileEntry] = []
    var selected: String?
    var loading = false
    var error: String?
    var hostID: UUID?
    init(side: PaneSide, path: [String]) { self.side = side; self.path = path }
    var pathString: String { joinPath(path) }
}

@Observable @MainActor
final class SFTPModel {
    let local = BrowserModel(side: .local, path: splitPath(NSHomeDirectory()))
    let remote = BrowserModel(side: .remote, path: [])
    var loaded = false
    var freeSpace: [PaneSide: String] = [:]

    func model(_ s: PaneSide) -> BrowserModel { s == .local ? local : remote }

    func refresh(_ s: PaneSide, store: AppStore) async {
        let m = model(s)
        m.loading = true; m.error = nil
        defer { m.loading = false }
        switch s {
        case .local:
            do { m.entries = try LocalFS.list(path: m.pathString) }
            catch { m.entries = []; m.error = error.localizedDescription }
        case .remote:
            guard let h = store.hosts.first(where: { $0.id == m.hostID }) else { m.entries = []; return }
            let a = store.makeAuth(for: h); defer { a.cleanup() }
            do {
                if m.path.isEmpty { m.path = splitPath(try await RemoteFS.homeDirectory(a.target)) }
                m.entries = try await RemoteFS.list(a.target, path: m.pathString)
            } catch {
                m.entries = []
                m.error = (error as? SSHError).flatMap { if case .failed(let x) = $0 { return x } else { return nil } } ?? error.localizedDescription
            }
        }
    }

    func enter(_ s: PaneSide, _ name: String, store: AppStore) { let m = model(s); m.path.append(name); m.selected = nil; Task { await refresh(s, store: store) } }
    func up(_ s: PaneSide, store: AppStore) { let m = model(s); guard !m.path.isEmpty else { return }; m.path.removeLast(); m.selected = nil; Task { await refresh(s, store: store) } }
    func jump(_ s: PaneSide, to count: Int, store: AppStore) { let m = model(s); m.path = Array(m.path.prefix(count)); m.selected = nil; Task { await refresh(s, store: store) } }

    /// Starts a transfer from `item`'s side to the other side's current directory.
    func transfer(_ item: DragItem, store: AppStore) {
        guard let h = store.hosts.first(where: { $0.id == remote.hostID }) else { return }
        let a = store.makeAuth(for: h)
        let t = a.target
        switch item.side {
        case .local:
            let url = URL(fileURLWithPath: item.path)
            let dest = remote.pathString
            let job = TransferJob(name: item.name, route: "\(item.path) → \(h.label):\(dest)", isUpload: true) { token, progress in
                try await Task.detached { try Transfer.upload(local: url, remoteDir: dest, target: t, token: token, progress: progress) }.value
            }
            job.cleanup = a.cleanup; store.transfers.enqueue(job)
        case .remote:
            let dest = URL(fileURLWithPath: local.pathString), rp = item.path, isDir = item.isDir
            let job = TransferJob(name: item.name, route: "\(h.label):\(rp) → \(dest.path)", isUpload: false) { token, progress in
                try await Transfer.download(remotePath: rp, isDir: isDir, localDir: dest, target: t, token: token, progress: progress)
            }
            job.cleanup = a.cleanup; store.transfers.enqueue(job)
        }
    }
}

struct SFTPView: View {
    @Environment(AppStore.self) private var store
    @State private var model = SFTPModel()
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 1) {
                BrowserPane(model: model, side: .local)
                BrowserPane(model: model, side: .remote)
            }.background(Tk.sep)
            if !store.transfers.jobs.isEmpty { TransferQueueView() }
        }.background(Tk.win)
        .task {
            if let p = store.sftpPick { model.remote.hostID = p }
            if model.remote.hostID == nil { model.remote.hostID = store.hosts.first(where: { $0.status == .online })?.id ?? store.hosts.first?.id }
            await model.refresh(.local, store: store); await model.refresh(.remote, store: store)
            store.transfers.onCompleted = { job in
                let s: PaneSide = job.isUpload ? .remote : .local
                Task { await model.refresh(s, store: store) }
            }
        }
    }
}

struct BrowserPane: View {
    @Environment(AppStore.self) private var store
    let model: SFTPModel
    let side: PaneSide
    @State private var targeted = false
    var m: BrowserModel { model.model(side) }

    var body: some View {
        VStack(spacing: 0) {
            header
            breadcrumb
            HStack(spacing: 8) {
                Color.clear.frame(width: 18)
                Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                Text("Size").frame(width: 64, alignment: .trailing)
                Text("Date Modified").frame(width: 110, alignment: .leading)
            }.font(.system(size: 11, weight: .semibold)).foregroundStyle(Tk.text3).padding(.horizontal, 20).frame(height: 24)
                .overlay(alignment: .bottom) { Rectangle().fill(Tk.sep).frame(height: 0.5) }
            content
            Text(footer).font(.system(size: 11)).foregroundStyle(Tk.text3).padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading).frame(height: 24).background(Tk.toolbar)
                .overlay(alignment: .top) { Rectangle().fill(Tk.sep).frame(height: 0.5) }
        }
        .background(Tk.win)
        .overlay { if targeted { dropOverlay } }
        .dropDestination(for: DragItem.self) { items, _ in
            for it in items where it.side != side { model.transfer(it, store: store) }
            return items.contains { $0.side != side }
        } isTargeted: { t in targeted = t }
    }

    var dropLabel: String { side == .remote ? "Upload to \(m.pathString)" : "Download to \(m.pathString)" }
    var dropOverlay: some View {
        ZStack(alignment: .bottom) {
            Rectangle().strokeBorder(Tk.accent, lineWidth: 2).background(Tk.accent.opacity(0.07))
            Text(dropLabel).font(.system(size: 12, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 5).background(Capsule().fill(Tk.accent)).padding(.bottom, 40)
        }.allowsHitTesting(false)
    }

    var header: some View {
        HStack(spacing: 8) {
            if side == .local {
                Image(systemName: "laptopcomputer").foregroundStyle(Tk.accent)
                Text("Local").fontWeight(.semibold)
                Text("\(Host_name)").foregroundStyle(Tk.text3).lineLimit(1)
            } else {
                Image(systemName: "server.rack").foregroundStyle(Tk.accent)
                Text("Remote").fontWeight(.semibold)
                StatusDot(color: store.hosts.first { $0.id == m.hostID }?.status.color ?? Tk.text3)
                @Bindable var mm = m
                Picker("", selection: $mm.hostID) {
                    ForEach(store.hosts) { Text($0.label).tag(Optional($0.id)) }
                }.labelsHidden().frame(maxWidth: 200)
                    .onChange(of: m.hostID) { m.path = []; Task { await model.refresh(.remote, store: store) } }
            }
            Spacer()
            IconButton(symbol: "arrow.clockwise", help: "Refresh") { Task { await model.refresh(side, store: store) } }
            IconButton(symbol: "arrow.up", help: "Enclosing Folder") { model.up(side, store: store) }.opacity(m.path.isEmpty ? 0.3 : 1)
        }.padding(.leading, 14).padding(.trailing, 10).frame(height: 40)
            .overlay(alignment: .bottom) { Rectangle().fill(Tk.sep).frame(height: 0.5) }
    }

    var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                crumb("/", count: 0)
                ForEach(Array(m.path.enumerated()), id: \.offset) { i, c in
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(Tk.text3)
                    crumb(c, count: i + 1)
                }
            }.padding(.horizontal, 10)
        }.frame(height: 28).overlay(alignment: .bottom) { Rectangle().fill(Tk.sep).frame(height: 0.5) }
    }
    func crumb(_ label: String, count: Int) -> some View {
        Text(label).font(.system(size: 12, weight: count == m.path.count ? .semibold : .regular))
            .foregroundStyle(count == m.path.count ? Tk.text : Tk.text2).padding(.horizontal, 5).padding(.vertical, 2)
            .contentShape(Rectangle()).onTapGesture { model.jump(side, to: count, store: store) }
    }

    @ViewBuilder var content: some View {
        if m.loading && m.entries.isEmpty {
            Text(side == .remote ? "Connecting to \(store.hosts.first { $0.id == m.hostID }?.label ?? "host")…" : "Loading…").foregroundStyle(Tk.text2).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let e = m.error {
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle").font(.system(size: 26)).foregroundStyle(Tk.bad)
                Text(side == .remote ? "Can’t connect to \(store.hosts.first { $0.id == m.hostID }?.label ?? "host")" : "Can’t read folder").fontWeight(.semibold)
                Text(e).font(Tk.mono(11)).foregroundStyle(Tk.text2).multilineTextAlignment(.center).textSelection(.enabled)
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if m.entries.isEmpty {
            Text("Folder is empty").foregroundStyle(Tk.text3).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(m.entries.enumerated()), id: \.element.id) { i, e in row(e, i) }
                }.padding(.vertical, 2)
            }
        }
    }

    func row(_ e: FileEntry, _ i: Int) -> some View {
        let sel = m.selected == e.name
        let item = DragItem(side: side, path: (m.pathString == "/" ? "" : m.pathString) + "/" + e.name, name: e.name, isDir: e.isDir)
        return HStack(spacing: 8) {
            Image(systemName: icon(e.kind)).foregroundStyle(sel ? .white : (e.isDir ? Tk.accent : Tk.text2)).frame(width: 18)
            Text(e.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(e.isDir ? "—" : Fmt.size(Double(e.size))).font(.system(size: 12)).monospacedDigit().frame(width: 64, alignment: .trailing)
                .foregroundStyle(sel ? .white.opacity(0.85) : Tk.text2)
            Text(Fmt.fileDate(e.modified)).font(.system(size: 12)).lineLimit(1).frame(width: 110, alignment: .leading)
                .foregroundStyle(sel ? .white.opacity(0.85) : Tk.text2)
        }
        .padding(.horizontal, 14).frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 5).fill(sel ? Tk.accent : (i % 2 == 1 ? Tk.hover.opacity(0.5) : .clear)))
        .foregroundStyle(sel ? .white : Tk.text).padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if e.isDir { model.enter(side, e.name, store: store) } else { model.transfer(item, store: store) }
        }
        .onTapGesture { m.selected = e.name }
        .draggable(item)
        .accessibilityLabel(e.isDir ? "Folder \(e.name)" : "\(e.name), \(Fmt.size(Double(e.size)))")
    }

    func icon(_ k: FileKind) -> String {
        switch k { case .dir: "folder.fill"; case .code: "chevron.left.forwardslash.chevron.right"; case .archive: "archivebox"; case .image: "photo"; case .doc: "doc.text" }
    }
    var Host_name: String { Foundation.Host.current().localizedName ?? "This Mac" }
    var footer: String {
        let n = m.entries.count
        if side == .local, let v = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage {
            return "\(n) items, \(Fmt.size(Double(v))) available"
        }
        return "\(n) items"
    }
}

struct TransferQueueView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let tc = store.transfers
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Transfers").fontWeight(.semibold)
                Text(tc.summary).font(.system(size: 12)).foregroundStyle(Tk.text2)
                Spacer()
                Button("Clear Completed") { tc.clearCompleted() }.buttonStyle(SecondaryButtonStyle()).font(.system(size: 12))
            }.padding(.horizontal, 14).frame(height: 30).overlay(alignment: .bottom) { Rectangle().fill(Tk.sep).frame(height: 0.5) }
            ScrollView {
                VStack(spacing: 0) { ForEach(tc.jobs) { j in TransferRow(job: j) } }
            }
        }.frame(maxHeight: 200).fixedSize(horizontal: false, vertical: true).background(Tk.toolbar)
            .overlay(alignment: .top) { Rectangle().fill(Tk.sep).frame(height: 0.5) }
    }
}

struct TransferRow: View {
    @Environment(AppStore.self) private var store
    let job: TransferJob
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: job.isUpload ? "arrow.up" : "arrow.down").font(.system(size: 11, weight: .bold))
                .foregroundStyle(job.isUpload ? Tk.accent : Tk.ok).frame(width: 24, height: 24).background(Circle().fill(Tk.field))
            VStack(alignment: .leading, spacing: 0) {
                Text(job.name).fontWeight(.medium).lineLimit(1)
                Text(job.route).font(Tk.mono(11)).foregroundStyle(Tk.text3).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                ProgressView(value: job.pct).progressViewStyle(.linear).tint(barColor)
                Text("\(Int(job.pct * 100))%").font(.system(size: 11)).foregroundStyle(Tk.text2).monospacedDigit().frame(width: 34, alignment: .trailing)
            }.frame(width: 200)
            Text(detail).font(.system(size: 11)).foregroundStyle(detailColor).monospacedDigit().lineLimit(1).frame(width: 190, alignment: .leading)
            if job.isActive || job.isQueued {
                Button { store.transfers.cancel(job) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Tk.text3) }
                    .buttonStyle(.plain).help("Cancel").accessibilityLabel("Cancel transfer").frame(width: 22)
            } else { Color.clear.frame(width: 22) }
        }.padding(.horizontal, 14).frame(height: 42).overlay(alignment: .bottom) { Rectangle().fill(Tk.sep).frame(height: 0.5) }
    }
    var barColor: Color { switch job.state { case .failed: Tk.bad; case .done: Tk.ok; default: job.isUpload ? Tk.accent : Tk.ok } }
    var detailColor: Color { if case .failed = job.state { return Tk.bad }; return Tk.text2 }
    var detail: String {
        switch job.state {
        case .queued: return "Queued"
        case .running:
            var s = "\(Fmt.size(Double(job.done))) of \(Fmt.size(Double(job.total)))"
            if job.speed > 0 { s += " · \(Fmt.size(job.speed))/s" }
            if let e = job.eta { s += " · \(Fmt.eta(e))" }
            return s
        case .done: return "Completed · \(Fmt.size(Double(job.total)))"
        case .failed(let m): return m
        case .cancelled: return "Cancelled"
        }
    }
}
