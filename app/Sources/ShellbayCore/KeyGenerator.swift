import Foundation

public enum KeyType: String, CaseIterable, Identifiable, Sendable {
    case ed25519 = "ED25519", rsa = "RSA 4096", ecdsa = "ECDSA P-256"
    public var id: String { rawValue }
    public var hint: String {
        switch self {
        case .ed25519: return "Recommended. Fast, compact and secure."
        case .rsa: return "Widest compatibility with older servers."
        case .ecdsa: return "Elliptic curve, supported by most modern servers."
        }
    }
    var sshKeygenArgs: [String] {
        switch self { case .ed25519: return ["-t", "ed25519"]; case .rsa: return ["-t", "rsa", "-b", "4096"]; case .ecdsa: return ["-t", "ecdsa", "-b", "256"] }
    }
}

public struct GeneratedKey: Sendable { public var privateKey: String; public var publicKey: String; public var fingerprint: String }

public enum KeyToolError: Error, LocalizedError {
    case failed(String)
    public var errorDescription: String? { if case .failed(let m) = self { return m }; return nil }
}

/// Wraps /usr/bin/ssh-keygen so the output is guaranteed to be valid OpenSSH.
public enum KeyGenerator {
    @discardableResult
    static func run(_ args: [String]) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen"); p.arguments = args
        let out = Pipe(), err = Pipe(); p.standardOutput = out; p.standardError = err
        try p.run(); p.waitUntilExit()
        let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            throw KeyToolError.failed((String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "") + s)
        }
        return s
    }

    public static func generate(name: String, type: KeyType) throws -> GeneratedKey {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shellbay-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("key").path
        try run(type.sshKeygenArgs + ["-N", "", "-C", "\(name)@shellbay", "-f", path, "-q"])
        let priv = try String(contentsOfFile: path, encoding: .utf8)
        let pub = try String(contentsOfFile: path + ".pub", encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        return GeneratedKey(privateKey: priv, publicKey: pub, fingerprint: try fingerprint(ofPublicKey: pub))
    }

    public static func fingerprint(ofPublicKey pub: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shellbay-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("k.pub"); try (pub + "\n").write(to: f, atomically: true, encoding: .utf8)
        let out = try run(["-lf", f.path])
        return out.split(separator: " ").dropFirst().first.map(String.init) ?? ""
    }

    /// Derives public key + metadata from an existing unencrypted private key.
    public static func importKey(privateKey: String) throws -> (type: KeyType, publicKey: String, fingerprint: String) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shellbay-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("k")
        var text = privateKey.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        if !text.contains("\n") { text += "\n" }
        try text.write(to: f, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: f.path)
        let pub = try run(["-y", "-P", "", "-f", f.path]).trimmingCharacters(in: .whitespacesAndNewlines)
        let type: KeyType = pub.hasPrefix("ssh-ed25519") ? .ed25519 : pub.hasPrefix("ssh-rsa") ? .rsa : .ecdsa
        return (type, pub, try fingerprint(ofPublicKey: pub))
    }
}
