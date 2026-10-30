import Foundation

public enum AuthMethod: String, Codable, CaseIterable, Sendable { case key = "SSH Key", password = "Password" }
public enum HostStatus: String, Codable, Sendable { case online, connecting, offline }

public struct Host: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var label: String
    public var hostname: String
    public var port: Int
    public var username: String
    public var authMethod: AuthMethod
    public var keyRef: String?
    public var group: String
    public var tags: [String]
    public var colorHex: String
    public var osHint: String
    public var status: HostStatus
    public var createdAt: Date

    public init(id: UUID = UUID(), label: String, hostname: String, port: Int = 22, username: String,
                authMethod: AuthMethod = .key, keyRef: String? = nil, group: String = "Personal",
                tags: [String] = [], colorHex: String = "#0a84ff", osHint: String = "Ubuntu 24.04 LTS",
                status: HostStatus = .online, createdAt: Date = Date()) {
        self.id = id; self.label = label; self.hostname = hostname; self.port = port; self.username = username
        self.authMethod = authMethod; self.keyRef = keyRef; self.group = group; self.tags = tags
        self.colorHex = colorHex; self.osHint = osHint; self.status = status; self.createdAt = createdAt
    }

    /// `user@ip` or `user@ip:port` when the port is not 22.
    public var address: String { port == 22 ? "\(username)@\(hostname)" : "\(username)@\(hostname):\(port)" }
}

public struct SSHKeyMeta: Identifiable, Codable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var type: String
    public var fingerprint: String
    public var publicKey: String
    public var createdAt: Date
    public init(name: String, type: String, fingerprint: String, publicKey: String, createdAt: Date = Date()) {
        self.name = name; self.type = type; self.fingerprint = fingerprint; self.publicKey = publicKey; self.createdAt = createdAt
    }
    /// `SHA256:q3Vb…8kZt` style shortened fingerprint.
    public var shortFingerprint: String {
        guard fingerprint.count > 18 else { return fingerprint }
        return String(fingerprint.prefix(11)) + "…" + String(fingerprint.suffix(4))
    }
}

public struct Snippet: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var command: String
    public var tags: [String]
    public init(id: UUID = UUID(), name: String, command: String, tags: [String] = []) {
        self.id = id; self.name = name; self.command = command; self.tags = tags
    }
}

public let defaultGroups = ["Production", "Staging", "Personal"]
public let colorChoices: [(name: String, hex: String)] = [
    ("Blue", "#0a84ff"), ("Green", "#30d158"), ("Yellow", "#ffd60a"), ("Orange", "#ff9f0a"),
    ("Red", "#ff453a"), ("Purple", "#bf5af2"), ("Graphite", "#8e8e93"),
]

public func parseTags(_ s: String) -> [String] {
    Array(s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(6))
}

public enum Seed {
    private static func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: y, month: m, day: day, hour: 12))!
    }
    public static let hosts: [Host] = [
        Host(label: "web-prod-01", hostname: "10.0.1.11", username: "ubuntu", authMethod: .key, keyRef: "id_ed25519", group: "Production", tags: ["nginx", "docker"], colorHex: "#ff453a", osHint: "Ubuntu 24.04 LTS", status: .online),
        Host(label: "web-prod-02", hostname: "10.0.1.12", username: "ubuntu", authMethod: .key, keyRef: "id_ed25519", group: "Production", tags: ["nginx", "docker"], colorHex: "#ff453a", osHint: "Ubuntu 24.04 LTS", status: .online),
        Host(label: "db-prod", hostname: "10.0.2.20", username: "deploy", authMethod: .key, keyRef: "deploy_2026", group: "Production", tags: ["postgres"], colorHex: "#ff9f0a", osHint: "Ubuntu 22.04 LTS", status: .online),
        Host(label: "api-staging", hostname: "172.16.4.30", username: "deploy", authMethod: .key, keyRef: "deploy_2026", group: "Staging", tags: ["node"], colorHex: "#ffd60a", osHint: "Ubuntu 24.04 LTS", status: .connecting),
        Host(label: "db-staging", hostname: "172.16.4.40", port: 2222, username: "deploy", authMethod: .key, keyRef: "deploy_2026", group: "Staging", tags: ["postgres"], colorHex: "#ffd60a", osHint: "Ubuntu 22.04 LTS", status: .offline),
        Host(label: "vps-hcm", hostname: "103.97.125.14", username: "root", authMethod: .key, keyRef: "id_ed25519", group: "Personal", tags: ["vpn"], colorHex: "#0a84ff", osHint: "Ubuntu 24.04 LTS", status: .online),
        Host(label: "homelab-pi", hostname: "192.168.1.50", username: "pi", authMethod: .key, keyRef: "homelab", group: "Personal", tags: ["arm", "home"], colorHex: "#30d158", osHint: "Ubuntu 24.04 arm64", status: .online),
    ]
    public static let keys: [SSHKeyMeta] = [
        SSHKeyMeta(name: "id_ed25519", type: "ED25519", fingerprint: "SHA256:q3VbR1xYtDk0mH7sNfZc2uPaLw9eJ8kZt", publicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIq3VbR1xYtDk0mH7sNfZc2uPaLw9eJ8kZtQ1 id_ed25519@shellbay", createdAt: d(2026, 3, 14)),
        SSHKeyMeta(name: "deploy_2026", type: "ED25519", fingerprint: "SHA256:Lx9PaQ4wTb7nVc1dEoRz5HgYk3sMu2mWc", publicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILx9PaQ4wTb7nVc1dEoRz5HgYk3sMu2mWcQ2 deploy_2026@shellbay", createdAt: d(2026, 1, 9)),
        SSHKeyMeta(name: "id_rsa_legacy", type: "RSA 4096", fingerprint: "SHA256:7hTeUj2KpNx8Rb4vCw6YdLz1AoSg3FiQa1d", publicKey: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQ7hTeUj2KpNx8Rb4vCw6YdLz1AoSg3FiQa1d id_rsa_legacy@shellbay", createdAt: d(2023, 8, 22)),
        SSHKeyMeta(name: "homelab", type: "ECDSA P-256", fingerprint: "SHA256:Pn4sWy6TbGh9Zc3Xk1VqRe8LdMu5JaAve0R", publicKey: "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYPn4sWy6TbGh9Zc3Xk1VqRe8LdMu5JaAve0R homelab@shellbay", createdAt: d(2025, 6, 3)),
    ]
    public static let snippets: [Snippet] = [
        Snippet(name: "Update system", command: "sudo apt update && sudo apt upgrade -y", tags: ["apt", "maintenance"]),
        Snippet(name: "Tail nginx logs", command: "sudo tail -n 20 /var/log/nginx/access.log", tags: ["nginx", "logs"]),
        Snippet(name: "Restart Docker", command: "sudo systemctl restart docker && docker ps", tags: ["docker"]),
        Snippet(name: "Check disk usage", command: "df -h / && du -sh /var/log", tags: ["disk", "monitoring"]),
        Snippet(name: "List open ports", command: "sudo ss -tulpn", tags: ["network", "security"]),
    ]
}
