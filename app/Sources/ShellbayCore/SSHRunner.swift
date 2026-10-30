import Foundation

public struct SSHTarget: Sendable {
    public var host: String, user: String, port: Int
    public var identityFile: String?      // temp file path holding the private key
    public var timeout: Int
    public var keepAlive: Int
    /// Password auth through SSH_ASKPASS (BatchMode must be off).
    public var password = false
    public var env: [String: String] = [:]
    public init(host: String, user: String, port: Int, identityFile: String? = nil, timeout: Int = 15, keepAlive: Int = 30) {
        self.host = host; self.user = user; self.port = port; self.identityFile = identityFile; self.timeout = timeout; self.keepAlive = keepAlive
    }
    public var processEnv: [String: String] { ProcessInfo.processInfo.environment.merging(env) { $1 } }
    public var sshArgs: [String] {
        var a = ["-o", "BatchMode=\(password ? "no" : "yes")", "-o", "ConnectTimeout=\(timeout)", "-o", "StrictHostKeyChecking=accept-new", "-p", String(port)]
        if keepAlive > 0 { a += ["-o", "ServerAliveInterval=\(keepAlive)"] }
        if let f = identityFile { a += ["-i", f, "-o", "IdentitiesOnly=yes"] }
        a.append("\(user)@\(host)")
        return a
    }
}

public enum SSHError: Error, LocalizedError, Equatable {
    case failed(String)
    public var errorDescription: String? { if case .failed(let m) = self { return m }; return nil }
}

/// Short-lived temp file for a private key (0600), removed on `cleanup()`.
public final class TempKeyFile: @unchecked Sendable {
    public let path: String
    public init?(privateKey: String) {
        let p = FileManager.default.temporaryDirectory.appendingPathComponent("sb-" + UUID().uuidString).path
        var text = privateKey; if !text.hasSuffix("\n") { text += "\n" }
        guard FileManager.default.createFile(atPath: p, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600]) else { return nil }
        path = p
    }
    public func cleanup() { try? FileManager.default.removeItem(atPath: path) }
}

public enum SSHRunner {
    /// Runs a remote command, returning stdout. Throws SSHError with stderr on non-zero exit.
    public static func exec(_ t: SSHTarget, _ command: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            p.arguments = t.sshArgs + [command]; p.environment = t.processEnv
            let out = Pipe(), err = Pipe(); p.standardOutput = out; p.standardError = err; p.standardInput = FileHandle.nullDevice
            p.terminationHandler = { proc in
                let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if proc.terminationStatus == 0 { cont.resume(returning: o) }
                else { cont.resume(throwing: SSHError.failed(cleanError(e.isEmpty ? o : e))) }
            }
            do { try p.run() } catch { cont.resume(throwing: SSHError.failed(error.localizedDescription)) }
        }
    }

    static func cleanError(_ s: String) -> String {
        let l = s.split(separator: "\n").filter { !$0.hasPrefix("Warning: Permanently added") }
        return l.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    public static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

public struct FileEntry: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var isDir: Bool
    public var size: Int64
    public var modified: Date?
    public init(name: String, isDir: Bool, size: Int64, modified: Date?) { self.name = name; self.isDir = isDir; self.size = size; self.modified = modified }
    public var kind: FileKind {
        if isDir { return .dir }
        let n = name.lowercased()
        if n.range(of: #"\.(gz|zip|tar|iso|pkg|dmg|tgz|xz|bz2)$"#, options: .regularExpression) != nil { return .archive }
        if n.range(of: #"\.(png|jpe?g|gif|svg|heic|webp)$"#, options: .regularExpression) != nil { return .image }
        if n.range(of: #"\.(js|ts|swift|py|sh|json|ya?ml|conf|css|html|sql|plist|toml|c|h|go|rs)$"#, options: .regularExpression) != nil { return .code }
        return .doc
    }
    public static func sorted(_ a: [FileEntry]) -> [FileEntry] {
        a.sorted { ($0.isDir ? 0 : 1, $0.name.lowercased()) < ($1.isDir ? 0 : 1, $1.name.lowercased()) }
    }
}
public enum FileKind: Sendable { case dir, code, archive, image, doc }

public enum RemoteFS {
    public static func parseLS(_ text: String) -> [FileEntry] {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm"
        var out: [FileEntry] = []
        for line in text.split(separator: "\n") {
            let p = line.split(separator: " ", maxSplits: 7, omittingEmptySubsequences: true)
            guard p.count == 8, let first = p[0].first, "-dl".contains(first), let size = Int64(p[4]) else { continue }
            var name = String(p[7])
            if first == "l", let r = name.range(of: " -> ") { name = String(name[..<r.lowerBound]) }
            if name == "." || name == ".." { continue }
            out.append(FileEntry(name: name, isDir: first == "d" || first == "l" && name.hasSuffix("/"), size: size, modified: f.date(from: "\(p[5]) \(p[6])")))
        }
        return FileEntry.sorted(out)
    }

    public static func list(_ t: SSHTarget, path: String) async throws -> [FileEntry] {
        let out = try await SSHRunner.exec(t, "ls -laL --time-style=long-iso \(SSHRunner.shellQuote(path.isEmpty ? "/" : path))")
        return parseLS(out)
    }

    public static func homeDirectory(_ t: SSHTarget) async throws -> String {
        try await SSHRunner.exec(t, "pwd").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum LocalFS {
    public static func list(path: String) throws -> [FileEntry] {
        let url = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let items = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        return FileEntry.sorted(items.map { u in
            let v = try? u.resourceValues(forKeys: Set(keys))
            return FileEntry(name: u.lastPathComponent, isDir: v?.isDirectory ?? false, size: Int64(v?.fileSize ?? 0), modified: v?.contentModificationDate)
        })
    }
    public static func totalSize(of url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue { return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        var total: Int64 = 0
        if let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let u as URL in en { total += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        }
        return total
    }
}

public func joinPath(_ comps: [String]) -> String { "/" + comps.joined(separator: "/") }
public func splitPath(_ p: String) -> [String] { p.split(separator: "/").map(String.init) }
