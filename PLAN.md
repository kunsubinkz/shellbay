# Shellbay — Kế hoạch triển khai chi tiết (macOS native)

> Đọc `DESIGN.md` trước để nắm spec UI. File này mô tả **làm gì, theo thứ tự nào, dùng công nghệ gì và thế nào là xong** cho từng giai đoạn. Mỗi giai đoạn đủ nhỏ để giao cho Claude Code làm trong 1–3 phiên.

---

## 0. Quyết định kỹ thuật

| Hạng mục | Lựa chọn | Lý do |
|---|---|---|
| Ngôn ngữ / UI | **Swift 5.10+, SwiftUI** + AppKit bridge (`NSViewRepresentable`) | Native Sonoma/Sequoia: vibrancy, unified toolbar, menu bar |
| Target | macOS 14.0+ | Dùng được SwiftData, Observation (`@Observable`) và Swift Charts mới |
| Terminal emulator | **SwiftTerm** (`migueldeicaza/SwiftTerm`) | VT100/xterm đầy đủ, có sẵn `TerminalView` cho AppKit, hỗ trợ theme/cursor |
| SSH / SFTP | **Citadel** (`orlandos-nl/Citadel`, xây trên SwiftNIO SSH) | Pure Swift, có PTY shell, exec, SFTP, port forward. Phương án dự phòng: libssh2 qua `Shout`/wrapper C |
| Lưu dữ liệu | **SwiftData** | Lưu Host, Snippet, Group, KeyMetadata |
| Bí mật | **Keychain Services** (`SecItem*`) | Lưu private key, password và PIN |
| Mở khóa | **LocalAuthentication** (Touch ID) + PIN 4 số | Đáp ứng spec "khóa app bằng PIN", Touch ID là bonus |
| Biểu đồ | **Swift Charts** | `LineMark` + `AreaMark` |
| Settings | `@AppStorage` / `UserDefaults` | Theme, font, cursor, lockMin, keepAlive, timeout |
| Kiến trúc | MVVM + `@Observable`; tầng service tách riêng bằng protocol để mock | Có thể test và preview bằng dữ liệu giả lấy từ prototype |
| Phân phối | Developer ID + notarization; sandbox **tắt** ở MVP | SSH cần outbound network và đọc `~/.ssh`. Bật sandbox sau (Giai đoạn 12) |

### Cấu trúc thư mục đề xuất
```
Shellbay/
├─ App/                 ShellbayApp.swift, AppState.swift, Commands.swift (menu + shortcuts)
├─ DesignSystem/        Tokens.swift (màu/spacing/radius), TerminalTheme.swift, Components/ (Chip, StatusDot, Keycap, Toast, EmptyState)
├─ Models/              Host.swift, HostGroup.swift, SSHKeyMeta.swift, Snippet.swift (SwiftData @Model)
├─ Services/
│  ├─ SSH/              SSHConnection.swift, SSHSessionManager.swift, HostKeyVerifier.swift
│  ├─ SFTP/             SFTPClient.swift, LocalFileSystem.swift, TransferQueue.swift
│  ├─ Keychain/         KeychainStore.swift, KeyGenerator.swift
│  ├─ Metrics/          HostMetricsSampler.swift, ProcParsers.swift
│  └─ Security/         AppLockService.swift
├─ Features/
│  ├─ Sidebar/          SidebarView.swift
│  ├─ Hosts/            HostsView.swift, HostCard.swift, HostRow.swift, HostEditorSheet.swift
│  ├─ Workspace/        WorkspaceTabBar.swift, WorkspaceModel.swift, PaneSplitView.swift
│  ├─ Terminal/         TerminalPane.swift (NSViewRepresentable SwiftTerm), TerminalStatusBar.swift
│  ├─ Monitor/          MonitorView.swift, MetricCard.swift, MetricChart.swift, ProcessTable.swift
│  ├─ Keychain/         KeychainView.swift, GenerateKeySheet.swift, ImportKeySheet.swift
│  ├─ SFTP/             SFTPView.swift, FileBrowserPane.swift, TransferQueueView.swift
│  ├─ Snippets/         SnippetsView.swift, SnippetEditorSheet.swift, RunSnippetSheet.swift
│  └─ Settings/         SettingsView.swift (4 tab), LockScreenView.swift, PinSheet.swift
├─ Fixtures/            PreviewData.swift (port từ SEED/KEYS/SNIPS của prototype)
└─ Tests/               ShellbayTests (parsers, validators, queue), ShellbayUITests
```

---

## Giai đoạn 1 — Khung project & Design System (0.5–1 ngày)
**Mục tiêu:** tạo cửa sổ rỗng đúng chất macOS, có đủ token màu và chữ.

1. Tạo Xcode project `Shellbay` (macOS App, SwiftUI, SwiftData). Thêm SPM: `SwiftTerm` và `Citadel`.
2. Viết `Tokens.swift`: toàn bộ màu dark/light theo bảng trong DESIGN.md.
   - Dùng `Color(nsColor:)` với dynamic provider theo `NSAppearance`.
   - Màu accent mặc định lấy từ `Color.accentColor`, có fallback `#0a84ff`.
3. Viết `TerminalTheme.swift`: struct có các trường `bg, fg, dim, red, green, blue, cursor` và 4 preset (Shellbay, Dracula, Nord, Solarized Dark), kèm hàm map sang 16 màu ANSI cho SwiftTerm.
4. Viết các component dùng chung:
   - `StatusDot`: 7pt, nhận trạng thái online/connecting/offline.
   - `TagChip`.
   - `Keycap`.
   - `Toast`: overlay ở đáy, tự ẩn sau 2s.
   - `EmptyState`: icon, tiêu đề, mô tả.
   - `ColorSwatchPicker`.
5. Viết `ShellbayApp`:
   - `WindowGroup`, `.windowStyle(.hiddenTitleBar)` hoặc `.titleBar` + `.windowToolbarStyle(.unified(showsTitle: true))`.
   - Kích thước mặc định 1200×780, tối thiểu 900×560.
   - Appearance mặc định là dark, có tùy chọn System/Dark/Light (nút trong toolbar).

**Done khi:** app chạy, cửa sổ bo góc có traffic lights, chuyển dark/light đúng màu token, có SwiftUI Preview cho từng component.

---

## Giai đoạn 2 — Data model & Sidebar (1 ngày)
1. Tạo các SwiftData model:
   - `Host`: id, label, hostname, port=22, username, authMethod(.key/.password), keyRef, group, tags:[String], colorHex, osHint, createdAt, lastConnectedAt.
   - `HostGroup`: các nhóm cố định Production/Staging/Personal ở MVP, cho phép tạo thêm sau.
   - `Snippet`: id, name, command, tags.
   - `SSHKeyMeta`: id, name, type, fingerprint, createdAt, keychainRef.
2. Viết `PreviewData`: port 7 host mẫu và 4 key mẫu từ prototype (xem `SEED`, `KEYS`, `SEED_META`), cùng 5 snippet (`SNIPS`).
3. Viết `SidebarView` bằng `NavigationSplitView` + `List(selection:)`, style `.sidebar`, gồm 2 `Section` (Favorites, Groups) và Settings ghim ở đáy (`safeAreaInset(edge: .bottom)`).
   - Badge số đếm dùng `.badge()`.
4. Viết `AppState` (`@Observable`): `selection: SidebarItem` (hosts/group(x)/keychain/snippets/sftp/portForwarding/settings) và `activeTabID`.

**Done khi:** click sidebar chuyển được view (các mục chưa làm hiện `EmptyState` "Coming soon"), đếm số host theo nhóm đúng.

---

## Giai đoạn 3 — Hosts list, tìm kiếm, context menu (1–1.5 ngày)
1. Viết `HostsView`:
   - Nhóm theo group bằng `LazyVGrid(columns: [.adaptive(minimum: 232)], spacing: 10)`.
   - Chế độ List dùng `Table` hoặc `List` với các cột theo DESIGN.md.
2. Viết `HostCard` theo spec: logo OS, tên + ô màu, `user@ip`, tag, footer trạng thái. Có các trạng thái hover, selected, focus ring.
3. Search: `.searchable(text:placement: .toolbar)`, lọc theo label, hostname, username, group, tags, OS. Gán `⌘F` bằng `.keyboardShortcut` trong `CommandGroup(replacing: .textEditing)` hoặc `FocusState`.
4. Context menu (`.contextMenu`): Connect `⌘O`, Edit… `⌘E`, Duplicate `⌘D`, Divider, Delete `⌘⌫`. Delete phải xác nhận bằng `confirmationDialog`.
5. Gesture: double-click (`onTapGesture(count: 2)`) gọi `WorkspaceModel.open(host:)`; Return mở host đang chọn.
6. Toolbar: segmented Grid/List, nút "+" (`⌘N`), nút appearance.

**Done khi:** lọc thật hoạt động, context menu và phím tắt chạy, đã test cả 2 chế độ hiển thị.

---

## Giai đoạn 4 — Host editor sheet (1 ngày)
1. Viết `HostEditorSheet` (`.sheet`), dùng `Form` + `LabeledContent` căn phải label (110pt):
   - Label\*, Hostname/IP\* + Port trên cùng một dòng, Username\*.
   - Authentication: `Picker(.segmented)` chọn Key hoặc Password. Key lấy từ danh sách `SSHKeyMeta`; Password dùng `SecureField`.
   - Group, Tags (token field `NSTokenField` qua bridge, hoặc text cách nhau bằng dấu phẩy kèm preview chip), Color (7 swatch).
2. Viết `HostValidator` (pure function để unit test):
   - Label không rỗng và không trùng.
   - Hostname khớp regex `^[a-zA-Z0-9.\-:]+$`.
   - Port trong khoảng 1–65535.
   - Username không rỗng.
   - Password bắt buộc nếu chọn auth bằng password.
3. Hiển thị lỗi theo spec: chỉ hiện sau lần Save đầu tiên, sau đó cập nhật realtime.
4. Lưu password vào Keychain (`kSecClassGenericPassword`, service `com.shellbay.host.<id>`); **không lưu vào SwiftData**.
5. Thêm Duplicate (tên mới thêm hậu tố `-copy`).

**Done khi:** có unit test cho validator; tạo, sửa, nhân bản, xóa host đều lưu bền; password nằm trong Keychain.

---

## Giai đoạn 5 — SSH core & Terminal tabs (3–4 ngày) ⭐ quan trọng nhất
1. Viết `SSHConnection` (actor) bọc Citadel:
   - `connect(host:, auth:, timeout:)`.
   - Mở PTY shell `xterm-256color` theo cols/rows.
   - Hàm `resize`, `write(Data)` và `AsyncStream<Data>` cho output.
   - Keep-alive theo setting (`ServerAliveInterval`), timeout theo setting.
2. Viết `HostKeyVerifier`:
   - Đọc và ghi file `~/.ssh/known_hosts` (hoặc store riêng của app).
   - Lần đầu gặp host thì hiện sheet "Trust this host?" kèm fingerprint SHA256.
   - Nếu key thay đổi thì chặn và hiện cảnh báo đỏ.
3. Xác thực:
   - Private key lấy từ Keychain, hỗ trợ OpenSSH ed25519, RSA và ECDSA; có passphrase thì hỏi khi cần.
   - Password lấy từ Keychain.
   - Phase 2 bổ sung ssh-agent.
4. Viết `TerminalPane` (`NSViewRepresentable` bọc `SwiftTerm.TerminalView`):
   - Font `NSFont.monospacedSystemFont(ofSize: settings.fontSize)`.
   - Áp theme ANSI, cursor style (`.blinkBlock/.blinkBar/.blinkUnderline`).
   - Chuyển input qua `send`, nhận output qua `feed`; hỗ trợ copy/paste và selection.
5. Viết `WorkspaceModel`:
   - `tabs: [WorkspaceTab]`; mỗi `WorkspaceTab` có `panes: [TerminalSession]`, `axis`, `focusedPane` và `view: .terminal/.monitor`.
   - API: `open(host:)` (focus tab nếu host đã mở), `newTab(host:)`, `close(tab:)`, `split(.right/.down)` (tối đa 4 pane), `closePane`.
6. Viết `WorkspaceTabBar`: tab home và tab session (nút ×, chấm trạng thái, icon split), nút "+" mở popover chọn host (`⌘T`). Có thể cân nhắc dùng native window tabbing (`NSWindow.tabbingMode`), nhưng prototype là tab bar trong cửa sổ.
7. Viết `PaneSplitView`: `HSplitView`/`VSplitView`, hoặc `SplitView` tự viết có divider 1px; pane đang focus có viền accent 2px ở trên, pane khác mờ đi.
8. Trạng thái kết nối:
   - connecting thì hiện spinner trong terminal.
   - Thất bại thì in lỗi màu đỏ và hiện nút **Reconnect** ở status bar.
   - `exit` thì hiện "Disconnected".
9. Viết `TerminalStatusBar`:
   - `user@host`.
   - Latency: đo RTT bằng cách gửi keep-alive hoặc exec `true` mỗi 2s.
   - Thời gian đã kết nối `HH:MM:SS`, keep-alive, OS (đọc `/etc/os-release` bằng exec channel lúc kết nối), `UTF-8`.

**Done khi:**
- Kết nối được tới một VPS Ubuntu 24.04 thật, `htop`/`vim` hiển thị đúng.
- Resize cửa sổ thì PTY resize theo.
- Mở nhiều tab, split 4 pane đều chạy độc lập.
- Có cảnh báo host key và có Reconnect.

---

## Giai đoạn 6 — Keychain (1.5 ngày)
1. Viết `KeyGenerator`:
   - ED25519 dùng `Curve25519.Signing` (CryptoKit).
   - ECDSA P-256 dùng `P256.Signing`.
   - RSA 4096 dùng `SecKeyCreateRandomKey`.
   - Xuất định dạng OpenSSH: private key dạng `-----BEGIN OPENSSH PRIVATE KEY-----`, public key dạng `ssh-ed25519 AAAA… name@shellbay`.
   - Fingerprint là `SHA256:` + base64 không padding của SHA256(public blob).
2. Viết `KeychainStore`:
   - Private key lưu dạng `kSecClassKey` hoặc generic password, có `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
   - `SSHKeyMeta` lưu trong SwiftData.
3. Viết `KeychainView`: bảng theo spec, dòng phụ "Used by N hosts" (query các Host có `keyRef`).
4. Copy public key bằng `NSPasteboard.general`, hiện toast "Đã copy public key".
5. Import: sheet có vùng dán key, hoặc `fileImporter` chọn file `~/.ssh/id_*`. Kiểm tra định dạng, hỏi passphrase nếu key mã hóa.
6. Delete: `confirmationDialog`, cảnh báo nếu có host đang dùng key. Sau khi xóa, các host đó chuyển sang trạng thái "Key missing" và hiện cảnh báo trên card.

**Done khi:** key tự tạo đăng nhập được vào server (sau khi thêm vào `authorized_keys`); import key OpenSSH có sẵn chạy được.

---

## Giai đoạn 7 — SFTP & transfer queue (2.5–3 ngày)
1. Viết `LocalFileSystem`: liệt kê thư mục bằng `FileManager` (`contentsOfDirectory` + `resourceValues` lấy size và ngày sửa), mặc định mở `~`.
2. Viết `SFTPClient` (Citadel SFTP): `list(path)`, `stat`, `download(remote, to:)`, `upload(local, to:)` dạng stream theo chunk (32–256 KB) và báo progress.
3. Viết `FileBrowserPane` (dùng chung cho hai cột):
   - Header (bên Remote có `Picker` chọn host), breadcrumb (có thể dùng `NSPathControl`), `Table` với các cột Name/Size/Date Modified.
   - Sắp xếp folder trước, rồi theo tên. Icon theo `UTType` / SF Symbols.
4. Kéo thả:
   - Dùng `.draggable`/`.dropDestination` với `Transferable` (payload gồm side, path, isDir).
   - Overlay khi đang kéo phía trên: viền accent và nhãn "Upload to …" hoặc "Download to …".
   - Phase 2: nhận file kéo từ Finder.
5. Viết `TransferQueue` (actor):
   - Tối đa 2 job song song, folder thì đệ quy.
   - Mỗi job báo progress, tốc độ (EMA) và ETA; cho phép cancel.
   - Nếu file đã tồn tại thì hỏi Replace / Keep Both / Skip.
6. Viết `TransferQueueView` theo spec (header tóm tắt, Clear Completed); hoàn tất thì refresh cột đích.
7. Lỗi: remote offline thì hiện empty state lỗi; lỗi quyền truy cập thì job báo "Permission denied".

**Done khi:**
- Upload và download được file 1 GB, progress mượt, cancel được, không treo UI.
- Copy được cả folder.

---

## Giai đoạn 8 — Snippets (1 ngày)
1. Viết `SnippetsView`: danh sách card, tìm kiếm qua search của toolbar, CRUD bằng sheet (Name\*, Command\*, Tags) và xóa có xác nhận.
2. Viết `RunSnippetSheet`: preview lệnh và danh sách host (host offline bị disable). Phase 2: chọn nhiều host để chạy broadcast.
3. Luồng Run:
   - Gọi `WorkspaceModel.open(host:)` và chờ session `.ready` (async, timeout lấy theo setting).
   - Gửi `command + "\n"` vào PTY.
4. Phase 2: hỗ trợ biến dạng `{{port}}`, hỏi giá trị trước khi chạy.

**Done khi:** Run snippet thì mở hoặc focus tab đúng host và lệnh được thực thi thật.

---

## Giai đoạn 9 — Monitor (2 ngày)
1. Viết `HostMetricsSampler`:
   - Chạy trên **exec channel riêng** (không dùng PTY), mỗi 2s chạy một lệnh gộp: `cat /proc/stat /proc/meminfo /proc/uptime /proc/loadavg; df -B1 /; ps -eo pid,user,%cpu,%mem,args --sort=-%cpu | head -9`.
   - Giữ 60 mẫu gần nhất (ring buffer).
2. Viết `ProcParsers` (pure, unit test bằng output mẫu):
   - CPU% tính từ chênh lệch 2 lần đọc `/proc/stat`.
   - Memory = MemTotal − MemAvailable.
   - Disk lấy từ `df`.
   - Uptime lấy từ `/proc/uptime`.
   - Danh sách process lấy từ `ps`.
3. Viết `MonitorView`:
   - 4 `MetricCard`, màu theo ngưỡng 60/80%.
   - 2 `MetricChart` (Swift Charts: `AreaMark` + `LineMark`, trục Y 0–100%, `.chartXAxis(.hidden)`, nhãn "2 min ago … now").
   - `ProcessTable` dùng `Table`.
4. Chuyển Terminal/Monitor bằng segmented control trong toolbar (`⌘1`/`⌘2`). Sampler chỉ chạy khi tab đang mở và host online; dừng khi đóng tab.

**Done khi:** số liệu khớp với `htop` trên server, CPU cách nhau ±3%; không rò rỉ channel.

---

## Giai đoạn 10 — Settings & App Lock (1.5–2 ngày)
1. Viết `SettingsView`: dùng scene `Settings {}` (`⌘,` có sẵn) **hoặc** giữ trong sidebar như prototype. Có 4 tab: Appearance, Shortcuts, Security, Connection.
2. **Appearance:**
   - Lưới 4 theme có preview, slider font 10–20pt, segmented cursor, khung preview trực tiếp.
   - Đổi theme thì phát `NotificationCenter` hoặc dùng state chung để mọi `TerminalPane` áp lại màu ngay.
3. **Shortcuts:** bảng chỉ đọc lấy từ cùng nguồn khai báo với `Commands.swift`, để không lệch nhau.
4. **Security:**
   - Viết `AppLockService`: PIN 4 số lưu **hash** (PBKDF2/SHA256 + salt) trong Keychain.
   - Theo dõi idle bằng `NSEvent.addLocalMonitorForEvents` cho chuột và phím; khóa sau `lockMin` phút. Khóa cả khi app ra background quá X phút hoặc màn hình khóa (`NSWorkspace.screensDidSleepNotification`).
   - `LockScreenView`: overlay `.ultraThinMaterial` toàn cửa sổ, 4 chấm PIN, nhập sai thì rung (shake) và báo lỗi. Có nút Touch ID qua `LAContext`.
   - Khi đang khóa: ẩn nội dung terminal (session vẫn giữ), chặn mọi shortcut.
5. **Connection:** keep-alive và timeout lưu bằng `@AppStorage`, `SSHConnection` đọc khi connect; hiển thị khối `ssh_config` tương ứng.

**Done khi:** setting được lưu bền; khóa và mở khóa hoạt động; đổi theme hoặc font thì terminal đang mở cập nhật ngay.

---

## Giai đoạn 11 — Menu bar, phím tắt, hoàn thiện (1 ngày)
1. `Commands.swift`: khai báo đủ phím tắt trong DESIGN.md (File: New Host, New Tab, Close Tab `⌘W`; View: Terminal/Monitor, Split; Host: Connect/Edit/Duplicate/Delete; Window: Lock).
2. Kiểm tra Accessibility: VoiceOver label cho icon button, focus ring, độ tương phản ≥ 4.5:1, hỗ trợ Dynamic Type ở mức hợp lý.
3. Kiểm tra empty state, loading, error cho mọi màn hình; toast thống nhất.
4. Hiệu năng: terminal output lớn (`cat` file 50 MB) không làm đứng UI; danh sách 500 host vẫn cuộn mượt.

---

## Giai đoạn 12 — Bảo mật, đóng gói, phát hành (1–2 ngày)
1. Hardened Runtime, ký Developer ID, notarize (`xcrun notarytool`), đóng gói DMG.
2. Bật thử App Sandbox: cần entitlement `com.apple.security.network.client`, đọc file qua security-scoped bookmark khi import key hoặc chọn thư mục SFTP.
3. Không log dữ liệu nhạy cảm; xóa password/PIN khỏi bộ nhớ sau khi dùng.
4. Cập nhật tự động: Sparkle 2.
5. Phase 2: đồng bộ iCloud (CloudKit cho SwiftData, không đồng bộ private key trừ khi người dùng bật).

---

## Ngoài MVP (backlog)
- **Port Forwarding** (sidebar đã có mục, hiện là placeholder): local/remote/dynamic (SOCKS) qua Citadel, kèm danh sách rule và công tắc bật/tắt.
- Import `~/.ssh/config` thành Hosts.
- Jump host / ProxyJump.
- Broadcast input tới nhiều pane cùng lúc.
- Ghi lại session (asciinema).
- Thêm theme terminal và cho phép import `.itermcolors`.

---

## Thứ tự & ước lượng
| # | Giai đoạn | Ước lượng | Phụ thuộc |
|---|---|---|---|
| 1 | Khung & Design System | 0.5–1 ngày | — |
| 2 | Model & Sidebar | 1 ngày | 1 |
| 3 | Hosts list | 1–1.5 ngày | 2 |
| 4 | Host editor | 1 ngày | 3 |
| 5 | SSH + Terminal | 3–4 ngày | 4 |
| 6 | Keychain | 1.5 ngày | 5 |
| 7 | SFTP | 2.5–3 ngày | 5 |
| 8 | Snippets | 1 ngày | 5 |
| 9 | Monitor | 2 ngày | 5 |
| 10 | Settings & Lock | 1.5–2 ngày | 5 |
| 11 | Menu & hoàn thiện | 1 ngày | 6–10 |
| 12 | Đóng gói | 1–2 ngày | 11 |

**Tổng: khoảng 17–22 ngày công** cho một người.

---

## Gợi ý prompt cho Claude Code (mỗi giai đoạn một phiên)
```
Đọc DESIGN.md và PLAN.md trong design_handoff_shellbay/. Mở Shellbay.dc.html để tham khảo UI.
Thực hiện "Giai đoạn N — <tên>" đúng phạm vi, theo cấu trúc thư mục trong PLAN.md.
Dùng token màu và kích thước trong DESIGN.md. Viết unit test cho phần logic thuần.
Khi xong: liệt kê file đã tạo hoặc sửa, cách chạy thử, và những điểm còn lệch so với spec.
```

## Checklist nghiệm thu cuối
- [ ] Dark/light đúng token; vibrancy ở sidebar, menu và lock screen.
- [ ] Mọi phím tắt trong DESIGN.md chạy được và có trong menu bar.
- [ ] Kết nối SSH thật bằng key và password; cảnh báo host key hoạt động.
- [ ] Tab, split 4 pane, Monitor số liệu thật.
- [ ] Generate, import, copy, delete key.
- [ ] SFTP kéo thả hai chiều; hàng đợi có progress, cancel, xử lý trùng tên.
- [ ] Snippet chạy được trên host đã chọn.
- [ ] Đổi theme, font, cursor thì áp ngay; PIN lock và auto-lock hoạt động.
- [ ] Không lưu bí mật ngoài Keychain; app đã ký và notarize.
