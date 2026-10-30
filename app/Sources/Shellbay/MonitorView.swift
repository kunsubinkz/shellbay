import SwiftUI
import Charts
import ShellbayCore

struct MonitorView: View {
    @Environment(AppStore.self) private var store
    let tab: WorkspaceTab
    var body: some View {
        let m = tab.monitor
        Group {
            if tab.focused?.status != .online && m.points.isEmpty {
                EmptyState(icon: "waveform.path.ecg", title: "Monitor Unavailable", message: m.error ?? "Connect to the host to see live metrics.")
            } else if let err = m.error, m.points.isEmpty {
                EmptyState(icon: "exclamationmark.triangle", title: "Monitor Unavailable", message: err)
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                            MetricCard(title: "CPU", value: String(format: "%.0f%%", m.cpu), pct: m.cpu, color: thresholdColor(m.cpu))
                            MetricCard(title: "Memory", value: m.mem.map { String(format: "%.1f GiB / %.1f", $0.usedGiB, $0.totalGiB) } ?? "—", pct: m.mem?.percent ?? 0, color: Tk.purple)
                            MetricCard(title: "Disk", value: m.disk.map { String(format: "%.0f%%", $0.percent) } ?? "—", pct: m.disk?.percent ?? 0, color: Tk.ok)
                            MetricCard(title: "Uptime", value: ProcParsers.formatUptime(m.uptime), pct: nil, color: Tk.accent)
                        }
                        HStack(spacing: 10) {
                            MetricChart(title: "CPU", points: m.points, keyPath: \.cpu, color: Tk.accent)
                            MetricChart(title: "Memory", points: m.points, keyPath: \.mem, color: Tk.purple)
                        }
                        ProcessTable(procs: m.procs)
                    }.padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Tk.win)
        .onAppear { startIfPossible() }
        .onChange(of: tab.focused?.status) { startIfPossible() }
        .onDisappear { tab.monitor.stop() }
    }
    func startIfPossible() { if let h = tab.focused?.host { tab.monitor.start(store: store, host: h) } }
    func thresholdColor(_ v: Double) -> Color { v > 80 ? Tk.bad : v > 60 ? Tk.warn : Tk.accent }
}

struct MetricCard: View {
    let title: String; let value: String; let pct: Double?; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11)).foregroundStyle(Tk.text2)
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit().tracking(-0.3).lineLimit(1).minimumScaleFactor(0.6)
            if let pct {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Tk.field)
                        Capsule().fill(color).frame(width: g.size.width * min(max(pct, 0), 100) / 100)
                            .animation(.easeOut(duration: 0.6), value: pct)
                    }
                }.frame(height: 5)
            } else { Color.clear.frame(height: 5) }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Tk.card))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Tk.cardBorder, lineWidth: 0.5))
    }
}

struct MetricChart: View {
    let title: String; let points: [MonitorPoint]; let keyPath: KeyPath<MonitorPoint, Double>; let color: Color
    var body: some View {
        let avg = points.isEmpty ? 0 : points.map { $0[keyPath: keyPath] }.reduce(0, +) / Double(points.count)
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title).font(.system(size: 12, weight: .semibold)); Spacer(); Text(String(format: "avg %.0f%%", avg)).font(.system(size: 11)).foregroundStyle(Tk.text2) }
            Chart {
                ForEach(Array(points.enumerated()), id: \.element.id) { i, p in
                    AreaMark(x: .value("t", i), y: .value(title, p[keyPath: keyPath])).foregroundStyle(color.opacity(0.16)).interpolationMethod(.monotone)
                    LineMark(x: .value("t", i), y: .value(title, p[keyPath: keyPath])).foregroundStyle(color).interpolationMethod(.monotone)
                }
            }
            .chartYScale(domain: 0...100).chartXScale(domain: 0...59)
            .chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { v in
                AxisGridLine().foregroundStyle(Tk.sep); AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%").font(.system(size: 9)).foregroundStyle(Tk.text3) } } }
            .chartXAxis(.hidden).frame(height: 130)
            HStack { Text("2 min ago"); Spacer(); Text("now") }.font(.system(size: 10)).foregroundStyle(Tk.text3)
        }.padding(14).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(Tk.card))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Tk.cardBorder, lineWidth: 0.5))
    }
}

struct ProcessTable: View {
    let procs: [ProcRow]
    var body: some View {
        VStack(spacing: 0) {
            row("PID", "User", "CPU%", "MEM%", "Command", header: true)
            ForEach(procs) { p in
                row(String(p.pid), p.user, String(format: "%.1f", p.cpu), String(format: "%.1f", p.mem), p.command, cpu: p.cpu)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Tk.cardBorder, lineWidth: 0.5))
    }
    func row(_ a: String, _ b: String, _ c: String, _ d: String, _ e: String, header: Bool = false, cpu: Double = 0) -> some View {
        HStack(spacing: 8) {
            Text(a).frame(width: 64, alignment: .leading); Text(b).frame(width: 80, alignment: .leading)
            Text(c).frame(width: 64, alignment: .trailing).foregroundStyle(cpu > 50 ? Tk.warn : (header ? Tk.text3 : Tk.text)).fontWeight(cpu > 10 ? .semibold : .regular)
            Text(d).frame(width: 64, alignment: .trailing)
            Text(e).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 8)
        }.font(header ? .system(size: 11, weight: .semibold) : Tk.mono(11.5)).foregroundStyle(header ? Tk.text3 : Tk.text)
            .padding(.horizontal, 14).frame(height: header ? 26 : 24).background(header ? Tk.card : .clear)
            .overlay(alignment: .bottom) { Rectangle().fill(Tk.sep).frame(height: 0.5) }
    }
}
