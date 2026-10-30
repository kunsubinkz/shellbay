import Foundation

public struct HostFormInput: Sendable {
    public var label = "", hostname = "", port = "22", username = "", password = ""
    public var authMethod: AuthMethod = .key
    public var keyRef: String? = nil
    public init() {}
}

public enum HostField: Hashable, Sendable { case label, hostname, port, username, password, key }

public enum HostValidator {
    /// Validates a host form. `existingLabels` must exclude the host being edited.
    public static func validate(_ f: HostFormInput, existingLabels: [String]) -> [HostField: String] {
        var e: [HostField: String] = [:]
        let label = f.label.trimmingCharacters(in: .whitespaces)
        if label.isEmpty { e[.label] = "Label is required." }
        else if existingLabels.contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) { e[.label] = "A host with this label already exists." }
        let host = f.hostname.trimmingCharacters(in: .whitespaces)
        if host.isEmpty { e[.hostname] = "Hostname or IP is required." }
        else if host.range(of: #"^[a-zA-Z0-9.\-:]+$"#, options: .regularExpression) == nil { e[.hostname] = "Hostname contains invalid characters." }
        if let p = Int(f.port.trimmingCharacters(in: .whitespaces)), (1...65535).contains(p) {} else { e[.port] = "Port must be 1–65535." }
        if f.username.trimmingCharacters(in: .whitespaces).isEmpty { e[.username] = "Username is required." }
        if f.authMethod == .password && f.password.isEmpty { e[.password] = "Password is required." }
        if f.authMethod == .key && (f.keyRef ?? "").isEmpty { e[.key] = "Choose an SSH key." }
        return e
    }

    public static func validateKeyName(_ name: String, existing: [String]) -> String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return "Name is required." }
        if n.range(of: #"^[\w.\-]+$"#, options: .regularExpression) == nil { return "Use letters, numbers, dots, dashes and underscores only." }
        if existing.contains(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) { return "A key with this name already exists." }
        return nil
    }

    public static func validatePrivateKey(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "Paste a private key." }
        let ok = (t.hasPrefix("-----BEGIN") && t.contains("PRIVATE KEY-----")) || t.hasPrefix("ssh-") || t.hasPrefix("ecdsa-")
        return ok ? nil : "Not a recognised private key format."
    }

    /// Returns a copy label for a duplicate, avoiding collisions.
    public static func duplicateLabel(of label: String, existing: [String]) -> String {
        var candidate = label + "-copy"
        var n = 2
        while existing.contains(candidate) { candidate = "\(label)-copy\(n)"; n += 1 }
        return candidate
    }
}
