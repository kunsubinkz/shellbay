import XCTest
@testable import ShellbayCore

final class ValidatorTests: XCTestCase {
    func form(_ mod: (inout HostFormInput) -> Void = { _ in }) -> HostFormInput {
        var f = HostFormInput(); f.label = "web"; f.hostname = "10.0.0.1"; f.port = "22"; f.username = "ubuntu"; f.keyRef = "k"; mod(&f); return f
    }
    func testValidFormHasNoErrors() { XCTAssertTrue(HostValidator.validate(form(), existingLabels: []).isEmpty) }
    func testRequiredFields() {
        let e = HostValidator.validate(form { $0.label = " "; $0.hostname = ""; $0.username = "" }, existingLabels: [])
        XCTAssertNotNil(e[.label]); XCTAssertNotNil(e[.hostname]); XCTAssertNotNil(e[.username])
    }
    func testDuplicateLabelCaseInsensitive() { XCTAssertNotNil(HostValidator.validate(form(), existingLabels: ["WEB"])[.label]) }
    func testHostnameRegex() {
        XCTAssertNotNil(HostValidator.validate(form { $0.hostname = "bad host!" }, existingLabels: [])[.hostname])
        XCTAssertNil(HostValidator.validate(form { $0.hostname = "fe80::1" }, existingLabels: [])[.hostname])
        XCTAssertNil(HostValidator.validate(form { $0.hostname = "my-host.example.com" }, existingLabels: [])[.hostname])
    }
    func testPortRange() {
        for bad in ["0", "65536", "abc", "", "-1"] { XCTAssertNotNil(HostValidator.validate(form { $0.port = bad }, existingLabels: [])[.port], bad) }
        for ok in ["1", "22", "65535"] { XCTAssertNil(HostValidator.validate(form { $0.port = ok }, existingLabels: [])[.port], ok) }
    }
    func testPasswordRequiredOnlyForPasswordAuth() {
        XCTAssertNotNil(HostValidator.validate(form { $0.authMethod = .password }, existingLabels: [])[.password])
        XCTAssertNil(HostValidator.validate(form { $0.authMethod = .password; $0.password = "x" }, existingLabels: [])[.password])
        XCTAssertNotNil(HostValidator.validate(form { $0.keyRef = nil }, existingLabels: [])[.key])
    }
    func testKeyNameAndPrivateKey() {
        XCTAssertNotNil(HostValidator.validateKeyName("", existing: []))
        XCTAssertNotNil(HostValidator.validateKeyName("a b", existing: []))
        XCTAssertNotNil(HostValidator.validateKeyName("id_x", existing: ["ID_X"]))
        XCTAssertNil(HostValidator.validateKeyName("id_x-1.pem", existing: []))
        XCTAssertNil(HostValidator.validatePrivateKey("-----BEGIN OPENSSH PRIVATE KEY-----\nabc"))
        XCTAssertNotNil(HostValidator.validatePrivateKey("hello"))
        XCTAssertNotNil(HostValidator.validatePrivateKey("  "))
    }
    func testDuplicateLabel() {
        XCTAssertEqual(HostValidator.duplicateLabel(of: "a", existing: ["a"]), "a-copy")
        XCTAssertEqual(HostValidator.duplicateLabel(of: "a", existing: ["a", "a-copy"]), "a-copy2")
    }
    func testParseTagsLimit() {
        XCTAssertEqual(parseTags(" a, b ,,c"), ["a", "b", "c"])
        XCTAssertEqual(parseTags("1,2,3,4,5,6,7,8").count, 6)
    }
}

final class ModelTests: XCTestCase {
    func testSeedMatchesPrototype() {
        XCTAssertEqual(Seed.hosts.count, 7); XCTAssertEqual(Seed.keys.count, 4); XCTAssertEqual(Seed.snippets.count, 5)
        XCTAssertEqual(Seed.hosts.filter { $0.group == "Production" }.count, 3)
        XCTAssertEqual(Seed.hosts.filter { $0.group == "Staging" }.count, 2)
        XCTAssertEqual(Seed.hosts.filter { $0.group == "Personal" }.count, 2)
    }
    func testAddressFormat() {
        XCTAssertEqual(Seed.hosts[0].address, "ubuntu@10.0.1.11")
        XCTAssertEqual(Seed.hosts[4].address, "deploy@172.16.4.40:2222")
    }
    func testShortFingerprint() { XCTAssertEqual(Seed.keys[0].shortFingerprint, "SHA256:q3Vb…8kZt") }
    func testHostCodableRoundTrip() throws {
        let d = try JSONEncoder().encode(Seed.hosts); XCTAssertEqual(try JSONDecoder().decode([ShellbayCore.Host].self, from: d), Seed.hosts)
    }
    func testThemes() {
        XCTAssertEqual(TerminalTheme.all.map(\.id), ["default", "dracula", "nord", "solarized"])
        XCTAssertEqual(TerminalTheme.named("nord").bg, "#2e3440"); XCTAssertEqual(TerminalTheme.named("zzz").id, "default")
    }
}

final class ParserTests: XCTestCase {
    let stat1 = "cpu  100 0 100 800 0 0 0 0 0 0\ncpu0 50 0 50 400 0 0 0 0 0 0\n"
    let stat2 = "cpu  200 0 200 1000 0 0 0 0 0 0\n"
    func testCPUPercent() {
        let a = ProcParsers.parseCPU(stat1)!, b = ProcParsers.parseCPU(stat2)!
        XCTAssertEqual(ProcParsers.cpuPercent(prev: a, cur: b), 50, accuracy: 0.001)   // 200 busy of 400
        XCTAssertEqual(ProcParsers.cpuPercent(prev: a, cur: a), 0)
    }
    func testMem() {
        let m = ProcParsers.parseMem("MemTotal:        4096000 kB\nMemFree:  100 kB\nMemAvailable:    1024000 kB\n")!
        XCTAssertEqual(m.percent, 75, accuracy: 0.001); XCTAssertEqual(m.totalGiB, 3.906, accuracy: 0.01)
    }
    func testUptimeAndFormat() {
        XCTAssertEqual(ProcParsers.parseUptime("2000000.55 1234.5\n"), 2000000.55)
        XCTAssertEqual(ProcParsers.formatUptime(90061), "1d 1h 1m")
    }
    func testDisk() {
        let d = ProcParsers.parseDisk("/dev/sda1 41875931136 17179869184 24696061952 42% /\n")!
        XCTAssertEqual(d.percent, 41.03, accuracy: 0.05)
        XCTAssertNotNil(ProcParsers.parseDisk("overlay 1005000000000 4000000000 900000000000 1% /\n"))   // docker/overlay, not under /dev
        XCTAssertNil(ProcParsers.parseDisk("Filesystem 1B-blocks Used Available Use% Mounted\n"))
    }
    func testPS() {
        let ps = """
            PID USER     %CPU %MEM COMMAND
           1544 www-data  9.0  6.8 node /srv/app/server.js
            811 root      0.3  0.3 nginx: master process /usr/sbin/nginx
           1611 www-data  4.2  4.2 node worker.js --flag
        """
        let r = ProcParsers.parsePS(ps)
        XCTAssertEqual(r.map(\.pid), [1544, 1611, 811]); XCTAssertEqual(r[2].command, "nginx: master process /usr/sbin/nginx")
    }
    func testCombined() {
        let out = stat1 + "@@SB@@\nMemTotal: 1000 kB\nMemAvailable: 500 kB\n@@SB@@\n10.5 3.0\n@@SB@@\n/dev/sda1 100 40 60 40% /\n@@SB@@\n  PID USER %CPU %MEM COMMAND\n 1 root 0.1 0.2 /sbin/init\n"
        let r = ProcParsers.parseCombined(out)
        XCTAssertNotNil(r); XCTAssertEqual(r?.procs.count, 1); XCTAssertEqual(r?.mem.percent, 50)
        XCTAssertNil(ProcParsers.parseCombined("garbage"))
    }
    func testParseLS() {
        let ls = """
        total 16
        drwxr-xr-x  4 ubuntu ubuntu 4096 2026-10-28 21:10 .
        drwxr-xr-x  3 root   root   4096 2025-02-02 10:00 ..
        drwxr-xr-x  3 ubuntu ubuntu 4096 2026-10-28 21:10 app
        -rwxr-xr-x  1 ubuntu ubuntu 2355 2026-10-24 15:50 deploy.sh
        -rw-r--r--  1 ubuntu ubuntu  412 2026-10-24 15:50 my file.tar.gz
        lrwxrwxrwx  1 root   root      7 2026-10-24 15:50 link -> /etc/x
        """
        let e = RemoteFS.parseLS(ls)
        XCTAssertEqual(e.map(\.name), ["app", "deploy.sh", "link", "my file.tar.gz"])
        XCTAssertTrue(e[0].isDir); XCTAssertEqual(e[1].size, 2355); XCTAssertEqual(e[1].kind, .code); XCTAssertEqual(e[3].kind, .archive)
        XCTAssertNotNil(e[1].modified)
    }
}

final class FormatTests: XCTestCase {
    func testSize() {
        XCTAssertEqual(Fmt.size(512), "512 bytes"); XCTAssertEqual(Fmt.size(2048), "2 KB")
        XCTAssertEqual(Fmt.size(48.2 * 1024 * 1024), "48.2 MB"); XCTAssertEqual(Fmt.size(2.6 * 1024 * 1024 * 1024), "2.60 GB")
    }
    func testDurationEta() {
        XCTAssertEqual(Fmt.duration(3725), "01:02:05"); XCTAssertEqual(Fmt.eta(0.2), "1s"); XCTAssertEqual(Fmt.eta(125), "2m 05s")
    }
    func testSpeedMeter() {
        var m = SpeedMeter(); m.update(done: 0, now: 0); m.update(done: 1000, now: 1)
        XCTAssertEqual(m.bytesPerSec, 1000, accuracy: 0.1); XCTAssertEqual(m.eta(remaining: 5000)!, 5, accuracy: 0.01)
    }
}

final class SecurityTests: XCTestCase {
    func testPinStore() throws {
        let s = PinStore(store: MemorySecretStore())
        XCTAssertFalse(s.isSet)
        try s.setPin("1234")
        XCTAssertTrue(s.isSet); XCTAssertTrue(s.verify("1234")); XCTAssertFalse(s.verify("4321"))
        s.clear(); XCTAssertFalse(s.verify("1234"))
        XCTAssertTrue(PinStore.isValidPin("0042")); XCTAssertFalse(PinStore.isValidPin("12a4")); XCTAssertFalse(PinStore.isValidPin("123"))
    }
    func testPinNotStoredInPlain() throws {
        let m = MemorySecretStore(); let s = PinStore(store: m); try s.setPin("9876")
        XCTAssertFalse((m.get(service: SecretService.pin, account: "pin") ?? "").contains("9876"))
    }
    func testRealKeychainRoundTrip() throws {
        let k = KeychainStore(); let acct = "test-\(UUID().uuidString)"
        do { try k.set("s3cret", service: "com.shellbay.test", account: acct) } catch { throw XCTSkip("Keychain unavailable in this environment: \(error)") }
        XCTAssertEqual(k.get(service: "com.shellbay.test", account: acct), "s3cret")
        k.delete(service: "com.shellbay.test", account: acct); XCTAssertNil(k.get(service: "com.shellbay.test", account: acct))
    }
}

final class KeyGenTests: XCTestCase {
    func testGenerateAllTypesAndImport() throws {
        for t in KeyType.allCases {
            let g = try KeyGenerator.generate(name: "unit", type: t)
            XCTAssertTrue(g.privateKey.contains("PRIVATE KEY-----"), t.rawValue)
            XCTAssertTrue(g.fingerprint.hasPrefix("SHA256:"), t.rawValue)
            XCTAssertTrue(g.publicKey.hasSuffix("unit@shellbay"))
            let r = try KeyGenerator.importKey(privateKey: g.privateKey)
            XCTAssertEqual(r.fingerprint, g.fingerprint); XCTAssertEqual(r.type, t)
        }
    }
    func testImportGarbageFails() { XCTAssertThrowsError(try KeyGenerator.importKey(privateKey: "-----BEGIN OPENSSH PRIVATE KEY-----\nbad\n-----END OPENSSH PRIVATE KEY-----")) }
}

final class LocalFSTests: XCTestCase {
    func testListAndSort() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("sbfs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d.appendingPathComponent("zdir"), withIntermediateDirectories: true)
        try Data(count: 10).write(to: d.appendingPathComponent("b.txt")); try Data(count: 5).write(to: d.appendingPathComponent("a.png"))
        defer { try? FileManager.default.removeItem(at: d) }
        let e = try LocalFS.list(path: d.path)
        XCTAssertEqual(e.map(\.name), ["zdir", "a.png", "b.txt"]); XCTAssertEqual(e[1].kind, .image)
        XCTAssertEqual(LocalFS.totalSize(of: d), 15)
        XCTAssertEqual(joinPath(["a", "b"]), "/a/b"); XCTAssertEqual(splitPath("/a/b/"), ["a", "b"])
    }
}
