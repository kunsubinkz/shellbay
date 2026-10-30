import Foundation

public enum Fmt {
    static let KB = 1024.0, MB = 1024.0 * 1024, GB = 1024.0 * 1024 * 1024
    public static func size(_ b: Double) -> String {
        b < KB ? "\(Int(b)) bytes" : b < MB ? "\(Int((b / KB).rounded())) KB" : b < GB ? String(format: "%.1f MB", b / MB) : String(format: "%.2f GB", b / GB)
    }
    public static func eta(_ s: Double) -> String {
        s >= 60 ? "\(Int(s) / 60)m \(String(format: "%02d", Int(s) % 60))s" : "\(max(1, Int(s.rounded(.up))))s"
    }
    public static func duration(_ interval: TimeInterval) -> String {
        let t = max(0, Int(interval)); return String(format: "%02d:%02d:%02d", t / 3600, t / 60 % 60, t % 60)
    }
    public static func shortDate(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "dd MMM yyyy"; return f.string(from: d)
    }
    public static func fileDate(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "dd MMM yyyy, HH:mm"; return f.string(from: d)
    }
}

public struct TerminalTheme: Identifiable, Hashable, Sendable {
    public var id: String; public var name: String
    /// nil means "follow appearance".
    public var bg: String?, fg: String?, dim: String?, red: String?, green: String?, blue: String?, cursor: String?
    public static let all: [TerminalTheme] = [
        .init(id: "default", name: "Shellbay"),
        .init(id: "dracula", name: "Dracula", bg: "#282a36", fg: "#f8f8f2", dim: "#6272a4", red: "#ff5555", green: "#50fa7b", blue: "#bd93f9", cursor: "#f8f8f2"),
        .init(id: "nord", name: "Nord", bg: "#2e3440", fg: "#d8dee9", dim: "#616e88", red: "#bf616a", green: "#a3be8c", blue: "#81a1c1", cursor: "#d8dee9"),
        .init(id: "solarized", name: "Solarized Dark", bg: "#002b36", fg: "#93a1a1", dim: "#586e75", red: "#dc322f", green: "#859900", blue: "#268bd2", cursor: "#93a1a1"),
    ]
    public static func named(_ id: String) -> TerminalTheme { all.first { $0.id == id } ?? all[0] }
}

public func hexToRGB(_ hex: String) -> (r: Double, g: Double, b: Double) {
    var s = hex; if s.hasPrefix("#") { s.removeFirst() }
    let v = UInt32(s, radix: 16) ?? 0
    return (Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255)
}
