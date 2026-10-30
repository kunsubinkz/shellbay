import Foundation

public struct TransferProgress: Sendable { public var done: Int64; public var total: Int64
    public init(done: Int64, total: Int64) { self.done = done; self.total = total } }

public final class CancelToken: @unchecked Sendable {
    private let lock = NSLock(); private var cancelled = false; private var proc: [Process] = []
    public init() {}
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func register(_ p: Process) { lock.lock(); proc.append(p); let c = cancelled; lock.unlock(); if c { p.terminate() } }
    public func cancel() { lock.lock(); cancelled = true; let ps = proc; lock.unlock(); ps.forEach { if $0.isRunning { $0.terminate() } } }
}

/// Byte-accurate transfers streamed through ssh (works with any sshd, no sftp-server needed).
public enum Transfer {
    static let chunk = 128 * 1024
    /// Writing to an ssh that has already exited must not kill the app.
    static let ignoreSigpipe: Void = { signal(SIGPIPE, SIG_IGN) }()

    public static func upload(local: URL, remoteDir: String, target t: SSHTarget, token: CancelToken, progress: @escaping @Sendable (TransferProgress) -> Void) throws {
        _ = ignoreSigpipe
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: local.path, isDirectory: &isDir)
        let total = max(LocalFS.totalSize(of: local), 1)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        let dest = SSHRunner.shellQuote(remoteDir)
        let cmd: String
        let reader: FileHandle?
        let tar = Process()
        let stdin = Pipe(), err = Pipe(); p.standardInput = stdin; p.standardError = err; p.standardOutput = FileHandle.nullDevice
        if isDir.boolValue {
            cmd = "tar -xf - -C \(dest)"
            tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            tar.arguments = ["-cf", "-", "-C", local.deletingLastPathComponent().path, local.lastPathComponent]
            tar.environment = ["COPYFILE_DISABLE": "1"]   // no AppleDouble ._ files on the server
            let tp = Pipe(); tar.standardOutput = tp; tar.standardError = FileHandle.nullDevice
            reader = tp.fileHandleForReading
            token.register(tar)
            try tar.run()
        } else {
            cmd = "cat > \(dest)/\(SSHRunner.shellQuote(local.lastPathComponent))"
            reader = try FileHandle(forReadingFrom: local)
        }
        p.arguments = t.sshArgs + [cmd]; p.environment = t.processEnv
        token.register(p)
        try p.run()
        var sent: Int64 = 0
        let w = stdin.fileHandleForWriting
        while !token.isCancelled {
            let data = reader?.readData(ofLength: chunk) ?? Data()
            if data.isEmpty { break }
            do { try w.write(contentsOf: data) } catch { break }
            sent += Int64(data.count)
            progress(TransferProgress(done: min(sent, total), total: total))
        }
        try? w.close(); try? reader?.close()
        p.waitUntilExit()
        if tar.isRunning { tar.terminate() }
        if token.isCancelled { throw SSHError.failed("Cancelled") }
        if p.terminationStatus != 0 {
            let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw SSHError.failed(SSHRunner.cleanError(e).isEmpty ? "Upload failed" : SSHRunner.cleanError(e))
        }
        progress(TransferProgress(done: total, total: total))
    }

    public static func download(remotePath: String, isDir: Bool, localDir: URL, target t: SSHTarget, token: CancelToken, progress: @escaping @Sendable (TransferProgress) -> Void) async throws {
        let q = SSHRunner.shellQuote(remotePath)
        let sizeCmd = isDir ? "du -sb \(q) | cut -f1" : "stat -c %s \(q)"
        let total = max(Int64((try? await SSHRunner.exec(t, sizeCmd))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 1, 1)
        let name = (remotePath as NSString).lastPathComponent
        let parent = SSHRunner.shellQuote((remotePath as NSString).deletingLastPathComponent.isEmpty ? "/" : (remotePath as NSString).deletingLastPathComponent)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global().async {
                do {
                    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                    p.environment = t.processEnv
                    p.arguments = t.sshArgs + [isDir ? "tar -cf - -C \(parent) \(SSHRunner.shellQuote(name))" : "cat \(q)"]
                    let out = Pipe(), err = Pipe(); p.standardOutput = out; p.standardError = err; p.standardInput = FileHandle.nullDevice
                    token.register(p)
                    var tar: Process?; var sink: FileHandle?; var tarIn: Pipe?
                    let dest = localDir.appendingPathComponent(name)
                    if isDir {
                        let tp = Process(); tp.executableURL = URL(fileURLWithPath: "/usr/bin/tar"); tp.arguments = ["-xf", "-", "-C", localDir.path]
                        let pipe = Pipe(); tp.standardInput = pipe; tp.standardError = FileHandle.nullDevice; tarIn = pipe
                        token.register(tp); try tp.run(); tar = tp; sink = pipe.fileHandleForWriting
                    } else {
                        FileManager.default.createFile(atPath: dest.path, contents: nil)
                        sink = try FileHandle(forWritingTo: dest)
                    }
                    try p.run()
                    var got: Int64 = 0
                    while !token.isCancelled {
                        let d = out.fileHandleForReading.readData(ofLength: chunk)
                        if d.isEmpty { break }
                        try sink?.write(contentsOf: d); got += Int64(d.count)
                        progress(TransferProgress(done: min(got, total), total: total))
                    }
                    try? sink?.close(); _ = tarIn
                    p.waitUntilExit(); tar?.waitUntilExit()
                    if token.isCancelled { if !isDir { try? FileManager.default.removeItem(at: dest) }; throw SSHError.failed("Cancelled") }
                    if p.terminationStatus != 0 {
                        if !isDir { try? FileManager.default.removeItem(at: dest) }
                        let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        throw SSHError.failed(SSHRunner.cleanError(e).isEmpty ? "Download failed" : SSHRunner.cleanError(e))
                    }
                    progress(TransferProgress(done: total, total: total))
                    cont.resume()
                } catch { cont.resume(throwing: error) }
            }
        }
    }
}

/// Exponential moving average speed tracker.
public struct SpeedMeter: Sendable {
    public private(set) var bytesPerSec: Double = 0
    private var lastT: TimeInterval? = nil, lastB: Int64 = 0
    public init() {}
    public mutating func update(done: Int64, now: TimeInterval) {
        defer { lastT = now; lastB = done }
        guard let lt = lastT, now > lt else { return }
        let inst = Double(done - lastB) / (now - lt)
        bytesPerSec = bytesPerSec == 0 ? inst : bytesPerSec * 0.7 + inst * 0.3
    }
    public func eta(remaining: Int64) -> Double? { bytesPerSec > 1 ? Double(remaining) / bytesPerSec : nil }
}
