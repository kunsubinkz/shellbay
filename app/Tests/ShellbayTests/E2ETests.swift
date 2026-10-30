import XCTest
@testable import ShellbayCore

/// Real SSH tests against a throwaway Ubuntu sshd (docker, localhost:2222).
/// Enabled with SB_E2E_KEY=<private key path>; skipped otherwise.
final class E2ETests: XCTestCase {
    var target: SSHTarget!
    override func setUpWithError() throws {
        guard let key = ProcessInfo.processInfo.environment["SB_E2E_KEY"] else { throw XCTSkip("SB_E2E_KEY not set") }
        target = SSHTarget(host: "127.0.0.1", user: "ubuntu", port: 2222, identityFile: key, timeout: 5, keepAlive: 0)
    }

    func testExecAndAuthFailure() async throws {
        let out = try await SSHRunner.exec(target, "echo hi && whoami")
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), "hi\nubuntu")
        var bad = target!; bad.port = 1
        do { _ = try await SSHRunner.exec(bad, "true"); XCTFail("should fail") } catch { XCTAssertTrue(error is SSHError) }
    }

    func testRemoteListing() async throws {
        let home = try await RemoteFS.homeDirectory(target)
        XCTAssertEqual(home, "/home/ubuntu")
        let e = try await RemoteFS.list(target, path: home)
        XCTAssertTrue(e.contains { $0.name == "app" && $0.isDir })
        let inApp = try await RemoteFS.list(target, path: home + "/app")
        XCTAssertEqual(inApp.first { $0.name == "hello.txt" }?.size, 6)
    }

    func testMetricsFromRealLinux() async throws {
        let out = try await SSHRunner.exec(target, ProcParsers.metricsCommand)
        let r = try XCTUnwrap(ProcParsers.parseCombined(out))
        XCTAssertGreaterThan(r.mem.totalKB, 0); XCTAssertGreaterThan(r.uptime, 0); XCTAssertNotNil(r.disk); XCTAssertFalse(r.procs.isEmpty)
        let out2 = try await SSHRunner.exec(target, ProcParsers.metricsCommand)
        let r2 = try XCTUnwrap(ProcParsers.parseCombined(out2))
        let pct = ProcParsers.cpuPercent(prev: r.cpu, cur: r2.cpu); XCTAssertTrue((0...100).contains(pct))
    }

    func testUploadDownloadFileAndFolder() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("sbe2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("up/sub"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let big = Data((0..<(3 * 1024 * 1024 + 123)).map { UInt8($0 % 251) })
        let file = tmp.appendingPathComponent("big.bin"); try big.write(to: file)
        try Data("x".utf8).write(to: tmp.appendingPathComponent("up/a.txt")); try Data("yy".utf8).write(to: tmp.appendingPathComponent("up/sub/b.txt"))

        let progress = Box()
        try Transfer.upload(local: file, remoteDir: "/home/ubuntu/app", target: target, token: CancelToken()) { progress.set($0) }
        XCTAssertEqual(progress.last?.done, Int64(big.count)); XCTAssertEqual(progress.last?.total, Int64(big.count))
        let listed = try await RemoteFS.list(target, path: "/home/ubuntu/app")
        XCTAssertEqual(listed.first { $0.name == "big.bin" }?.size, Int64(big.count))

        try Transfer.upload(local: tmp.appendingPathComponent("up"), remoteDir: "/home/ubuntu/app", target: target, token: CancelToken()) { _ in }
        let sub = try await RemoteFS.list(target, path: "/home/ubuntu/app/up/sub")
        XCTAssertEqual(sub.map(\.name), ["b.txt"])

        let dl = tmp.appendingPathComponent("dl"); try FileManager.default.createDirectory(at: dl, withIntermediateDirectories: true)
        try await Transfer.download(remotePath: "/home/ubuntu/app/big.bin", isDir: false, localDir: dl, target: target, token: CancelToken()) { _ in }
        XCTAssertEqual(try Data(contentsOf: dl.appendingPathComponent("big.bin")), big)
        try await Transfer.download(remotePath: "/home/ubuntu/app/up", isDir: true, localDir: dl, target: target, token: CancelToken()) { _ in }
        XCTAssertEqual(try String(contentsOf: dl.appendingPathComponent("up/sub/b.txt")), "yy")
    }

    func testCancelUpload() throws {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("sbc-\(UUID().uuidString)")
        try Data(count: 64 * 1024 * 1024).write(to: f); defer { try? FileManager.default.removeItem(at: f) }
        let tok = CancelToken()
        let t = target!
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { tok.cancel() }
        XCTAssertThrowsError(try Transfer.upload(local: f, remoteDir: "/tmp", target: t, token: tok) { _ in })
    }
}

final class Box: @unchecked Sendable {
    private let l = NSLock(); private var v: TransferProgress?
    func set(_ p: TransferProgress) { l.lock(); v = p; l.unlock() }
    var last: TransferProgress? { l.lock(); defer { l.unlock() }; return v }
}
