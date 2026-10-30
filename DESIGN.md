# Handoff: Shellbay — SSH client cho macOS

## Overview
Shellbay là SSH client native cho macOS (Sonoma/Sequoia), dark mode mặc định và có light mode. Prototype gồm các phần sau:
- **Hosts**: danh sách host dạng card/list, nhóm theo folder, có tìm kiếm, context menu và modal thêm/sửa host.
- **Terminal**: nhiều tab, split pane, terminal giả lập Ubuntu, thanh trạng thái.
- **Monitor**: CPU/RAM/Disk/Uptime, biểu đồ realtime, top process.
- **Keychain**: quản lý SSH key (generate, import, copy public key, delete).
- **SFTP**: hai cột Local/Remote, kéo thả, hàng đợi truyền file.
- **Snippets**: lệnh lưu sẵn, chạy trên host đã chọn.
- **Settings**: theme terminal, font, con trỏ, phím tắt, khóa PIN, keep-alive/timeout.

Kế hoạch triển khai chi tiết từng giai đoạn nằm trong **`PLAN.md`**.

## About the Design Files
Các file trong gói này là **bản thiết kế tham chiếu viết bằng HTML/CSS/JS**. Đây là prototype mô tả giao diện và hành vi mong muốn, **không phải code production để copy**. Nhiệm vụ là **dựng lại thiết kế này trong môi trường native macOS** (đề xuất SwiftUI + AppKit, xem `PLAN.md`) theo pattern chuẩn của nền tảng.

Toàn bộ dữ liệu trong prototype là giả: server, output lệnh, metrics, file tree, SSH key. App thật phải thay chúng bằng kết nối SSH/SFTP thật.

Cách mở prototype: đặt `Shellbay.dc.html` và `support.js` cùng một thư mục rồi mở bằng trình duyệt qua một static server, ví dụ `npx serve .` hoặc `python3 -m http.server`. Mở trực tiếp bằng `file://` có thể bị chặn import.

## Fidelity
**High-fidelity.** Màu, typography, spacing, trạng thái và tương tác đều đã chốt. Hãy dựng lại sát pixel nhưng dùng control native khi có tương đương (`NSSegmentedControl`, `Toggle(.switch)`, `Picker`, `NSSearchField`, `NSMenu`…). Control native được ưu tiên hơn việc vẽ tay giống hệt HTML.

---

## Screens / Views

### 0. Window shell (dùng chung)
- **Cửa sổ:** bo góc 12px, `titlebarAppearsTransparent`, unified toolbar (`.unifiedCompact`), traffic lights ở góc trái trên. Trong HTML chúng nằm ở sidebar, cách mép trái 20px, mỗi nút 12px, cách nhau 8px.
- **Kích thước:** prototype dùng 1200×780. Tối thiểu nên là 900×560.
- **Sidebar trái** (`NavigationSplitView`, rộng 224px):
  - Vibrancy dùng `.sidebar` material. Trong HTML là `rgba(40,40,42,.62)` + `backdrop-filter: blur(40px) saturate(180%)`. Light mode là `rgba(234,234,237,.68)`.
  - Nhóm **Favorites:** Hosts (kèm badge số host), Keychain, Snippets, SFTP, Port Forwarding.
  - Nhóm **Groups:** Production, Staging, Personal, mỗi mục kèm số host.
  - **Settings** ghim ở đáy, kèm gợi ý `⌘,`.
  - Mỗi item cao 28px, bo 6px, padding ngang 8px, icon 16px stroke 1.3 màu accent. Item được chọn có nền `rgba(255,255,255,.11)` (light: `rgba(0,0,0,.08)`). Tiêu đề nhóm cỡ 11px, weight 600, màu text3.
- **Toolbar** (cao 52px):
  - Bên trái: segmented Grid/List khi ở Hosts, hoặc segmented Terminal|Monitor + 2 nút split khi đang ở terminal.
  - Giữa: tiêu đề cửa sổ 13px semibold và subtitle 11px màu text2, ví dụ "7 hosts" hoặc "ubuntu@10.0.1.11".
  - Bên phải: nút đổi appearance, nút "+" (New Host, `⌘N`) và ô Search rộng 210px, cao 28px, bo 7px, có gợi ý `⌘F`.
- **Thanh tab** (cao 30px, chỉ hiện khi có ít nhất 1 session):
  - Tab "home" mang tên mục hiện tại.
  - Mỗi tab session có nút ×, chấm trạng thái 7px, tên host và icon split nếu tab đang chia pane.
  - Nút "+" ở cuối mở popover chọn host (`⌘T`).

### 1. Hosts
- **Nhóm theo folder:** mỗi nhóm có header gồm icon folder, tên (13px/600) và số host (12px, text3).
- **Grid:** `repeat(auto-fill, minmax(232px,1fr))`, gap 10px.
  - Card padding 12×14, bo 10px, nền `rgba(255,255,255,.04)`, viền 0.5px `rgba(255,255,255,.07)`.
  - Hover: nền `.07`. Được chọn: nền `rgba(10,132,255,.16)` + inset ring 1.5px accent.
  - Nội dung card:
    - Dòng đầu: logo Ubuntu 32px (#E95420), tên host (13px/600) và ô màu nhận diện 8×8 bo 2px.
    - Dòng `user@ip[:port]` dùng font SF Mono 11.5px màu text2.
    - Tag chip cỡ 10.5px, padding 1×7, bo 10px.
    - Footer: chấm trạng thái 7px, nhãn ("Online", "Connecting…", "Offline") và tên OS.
- **List:** mỗi dòng cao 36px, cột `22px | 1.2fr | 1.4fr | 1fr | 110px` (icon, tên, địa chỉ, OS, trạng thái).
- **Tương tác:**
  - Click để chọn; click ra ngoài để bỏ chọn.
  - **Double-click** để mở tab terminal. Nếu host đã có tab thì chuyển sang tab đó.
  - **Right-click** mở context menu rộng 200px, item cao 22px, hover nền accent chữ trắng. Các item: Connect `⌘O`, Edit… `⌘E`, Duplicate `⌘D`, separator, Delete `⌘⌫`.
  - Enter mở host đang chọn.
- **Search:** lọc theo name/ip/user/group/OS. Khi không có kết quả thì hiện "No Results / No hosts match “q”".

### 2. New / Edit Host (sheet)
- Sheet rộng 500px, bo 12px, nền `#2b2b2d` (light: `#f2f2f4`), đặt cách đỉnh cửa sổ 52px.
- Form 2 cột, cột label rộng 110px căn phải. Các trường:
  - **Label\*:** không trùng với host khác.
  - **Hostname/IP\*:** regex `^[a-zA-Z0-9.\-:]+$`.
  - **Port:** mặc định 22, nằm cùng dòng với Hostname, phải trong khoảng 1–65535.
  - **Username\*.**
  - **Authentication:** segmented **SSH Key | Password**.
    - SSH Key: dropdown chọn key từ Keychain, bên dưới là dòng gợi ý fingerprint và ngày tạo.
    - Password: secure field, bắt buộc nhập.
  - **Group:** Production, Staging, Personal.
  - **Tags:** phân tách bằng dấu phẩy, tối đa 6, có preview chip.
  - **Color:** 7 swatch 16px là Blue `#0a84ff`, Green `#30d158`, Yellow `#ffd60a`, Orange `#ff9f0a`, Red `#ff453a`, Purple `#bf5af2`, Graphite `#8e8e93`. Swatch đang chọn có ring 2px màu nền sheet cộng 1.5px màu swatch.
- **Validate khi bấm Save:** trường lỗi có viền `--bad` + ring 2px 30% alpha, và dòng lỗi 11px bên dưới.
- Enter để Save, Esc để Cancel.

### 3. Terminal
- **Pane:** font SF Mono, mặc định 13pt (chỉnh trong Settings), line-height 1.5, padding 10×14.
- **Kết nối giả:**
  - Dòng `$ ssh user@ip -p port` màu dim, sau đó "Connecting to …".
  - Thành công sau 0.9s (host đang "connecting" mất 2.6s), rồi hiện banner MOTD của Ubuntu 24.04.
  - Host offline thì báo "Connection refused" màu đỏ và hiện nút **Reconnect**.
- **Prompt:** `user@host` màu xanh lá semibold, `:`, cwd màu xanh dương, `$ ` (hoặc `# ` nếu là root).
- **Lệnh giả:** `ls [-l]`, `cd`, `pwd`, `whoami`, `hostname`, `uptime`, `uname -a`, `df -h`, `free -h`, `date`, `neofetch` (logo Ubuntu màu #E95420 kèm bảng info và 2 dải màu ANSI), `echo`, `history`, `clear`, `exit`, `help`.
- **Phím:** ↑/↓ duyệt history, ⌃L clear, ⌃C cancel.
- **Split pane:** `⌘D` chia phải, `⇧⌘D` chia xuống, tối đa 4 pane trên một trục.
  - Khi có từ 2 pane trở lên, mỗi pane có header cao 24px gồm chấm trạng thái, `user@host` và nút ×.
  - Pane đang focus có border-top 2px accent; pane khác bị làm mờ (opacity 0.6).
- **Con trỏ:** block (0.6em × 1.25em), bar (2px) hoặc underline (2px). Nhấp nháy `steps(1)` chu kỳ 1.1s, chỉ ở pane đang focus.
- **Thanh trạng thái** (cao 26px): chấm và trạng thái, `user@host`, latency (dao động mỗi 2s), thời gian đã kết nối `HH:MM:SS`, `keep-alive 30s`, OS, badge `UTF-8`.

### 4. Monitor (cùng tab với Terminal, chuyển bằng `⌘1`/`⌘2`)
- **4 thẻ số liệu:** `auto-fit minmax(170px,1fr)`.
  - CPU %: thanh tiến trình màu accent, chuyển vàng khi trên 60% và đỏ khi trên 80%.
  - Memory dạng "x.x GiB / tổng": thanh màu `#bf5af2`.
  - Disk: thanh màu `--ok`.
  - Uptime: tăng theo từng giây.
  - Giá trị cỡ 22px/600, tabular-nums.
- **2 biểu đồ đường** CPU và Memory:
  - Cập nhật mỗi 2s, lưu 60 điểm (2 phút). Có area fill 16% alpha, lưới 0/25/50/75/100%, nhãn trục Y và chữ "avg x%".
- **Top Processes:** 8 dòng xếp theo CPU giảm dần, cột `PID 64 | User 80 | CPU% 64 | MEM% 64 | Command 1fr`. CPU trên 50% chữ vàng, trên 10% in đậm.
- Nếu chưa kết nối thì hiện "Monitor Unavailable".

### 5. Keychain
- **Header:** "SSH Keys" kèm mô tả; nút **Import Key…** (nút phụ) và **Generate Key** (nút accent).
- **Bảng:** `Name 1.4fr | Type 110 | Fingerprint 1.2fr | Created 100 | Actions 76`.
  - Ô Name có dòng phụ "Used by N hosts".
  - Fingerprint rút gọn dạng `SHA256:q3Vb…8kZt`, font mono.
  - Actions: copy public key (hiện toast **"Đã copy public key"** trong 2s) và delete (có xác nhận, nút đỏ, cảnh báo nếu key đang được host dùng).
- **Modal Generate:** Name (bắt buộc, regex `[\w.\-]+`, không trùng) và Type segmented ED25519 / RSA 4096 / ECDSA P-256 kèm dòng giải thích.
- **Modal Import:** Name và vùng dán private key, phải bắt đầu bằng `-----BEGIN … PRIVATE KEY-----`, `ssh-` hoặc `ecdsa-`.

### 6. SFTP
- **Hai cột** `1fr 1fr`, ngăn cách 1px. Mỗi cột từ trên xuống:
  - Header cao 40px. Bên Local: "Local — minh’s MacBook Pro". Bên Remote: "Remote", chấm trạng thái và dropdown chọn host. Có nút ↑ lên thư mục cha.
  - Breadcrumb cao 28px, mỗi đoạn bấm được.
  - Header cột cao 24px: `18 | Name minmax(80px,1fr) | Size minmax(0,64px) | Date minmax(0,110px)`.
  - Danh sách: mỗi dòng cao 24px, bo 5px, sọc xen kẽ, dòng chọn nền accent chữ trắng. Icon theo loại: folder (tô màu accent), code, archive, image, document.
  - Footer: "N items, X GB available".
- **Double-click:** folder thì đi vào trong, file thì chuyển sang cột còn lại.
- **Kéo thả** giữa hai cột:
  - Cột đích hiện viền inset 2px accent, nền accent 7% và nhãn "Upload to /path" hoặc "Download to /path".
  - Thả vào cột nguồn không làm gì.
- **Hàng đợi transfer** (cao tối đa 200px, nằm dưới hai cột):
  - Header "Transfers" kèm "N active · N queued · N completed" và nút "Clear Completed".
  - Mỗi dòng: icon ↑ (upload, màu accent) hoặc ↓ (download, màu ok), tên, route dạng mono, thanh tiến trình cao 5px, %, "x of y · speed/s · ETA" và nút cancel.
  - Tối đa 2 file chạy song song.
- **Remote offline:** hiện lỗi "connect to host … Connection refused".

### 7. Snippets
- **Card:** tên, tag chip, nút Edit, nút Delete, nút **Run** (có icon ▶) và khung lệnh mono nền terminal.
- **Modal thêm/sửa:** Name\*, Command\* (textarea), Tags.
- **Modal Run:** preview lệnh và danh sách host để chọn một (host offline bị làm mờ, không chọn được). Bấm Run thì mở hoặc focus tab terminal, chờ session ready, gõ lệnh vào prompt rồi in output.
- **5 snippet mẫu:**
  - Update system: `sudo apt update && sudo apt upgrade -y`
  - Tail nginx logs
  - Restart Docker
  - Check disk usage
  - List open ports (`ss -tulpn`)

### 8. Settings (4 tab segmented ở giữa, nội dung rộng tối đa 680px)
- **Appearance:**
  - 4 theme terminal, mỗi theme có card preview cao 82px; theme đang chọn có ring 2px accent và dấu ✓.
  - Font size dạng slider 10–20pt.
  - Cursor dạng segmented Block / Bar / Underline.
  - Khung Preview trực tiếp.
  - Đổi theme thì mọi terminal đổi màu ngay.
- **Shortcuts:** 3 nhóm (General / Hosts / Terminal). Phím hiển thị dạng keycap 22px, nền nút, viền 0.5px.
- **Security:**
  - Công tắc "Require PIN to open Shellbay": bật thì mở dialog đặt PIN 4 số (nhập 2 lần); tắt thì phải nhập PIN hiện tại.
  - Auto-lock after: 1, 2, 5, 10, 15 hoặc 30 phút không thao tác.
  - Nút Change PIN… và Lock Now (`⌃⌘L`).
  - **Lock screen:** lớp phủ vibrancy toàn cửa sổ, icon khóa trong ô 64px, "Shellbay is Locked", 4 chấm PIN 11px. Nhập sai thì báo "Incorrect PIN. Try again." màu đỏ.
- **Connection:** Keep-alive interval (Off, 15, 30, 60, 120 s) và Connection timeout (5, 10, 15, 30, 60 s), kèm khối `ssh_config` tương ứng.

---

## Interactions & Behavior (tổng hợp)
- **Phím tắt:**
  - `⌘N` New Host, `⌘F` Search, `⌘,` Settings, `⌃⌘L` Lock.
  - `⌘O` / `⌘E` / `⌘D` / `⌘⌫` cho host đang chọn.
  - `⌘T` New Tab, `⌘D` / `⇧⌘D` Split, `⌘1` / `⌘2` Terminal / Monitor, `Esc` đóng menu, sheet hoặc dialog.
  - App native cần khai báo tất cả trong menu bar (`CommandMenu`).
- **Transitions:** toggle 150ms; thanh tiến trình của card metric `width .6s ease`; con trỏ nhấp nháy `steps(1)` 1.1s. Các phần khác không có animation trang trí.
- **Toast:** nổi ở đáy giữa, cách đáy 44px, nền material, icon check màu `--ok`, tự ẩn sau 2s.
- **Validation:** chỉ chạy khi bấm nút xác nhận; sau đó lỗi cập nhật realtime theo từng lần sửa.
- **Lưu trữ:** Settings được lưu vào localStorage (app thật dùng `UserDefaults` / `@AppStorage`). Các dữ liệu khác chỉ tồn tại trong phiên (app thật dùng SwiftData, xem PLAN.md).

## State Management (mô hình prototype → app thật)
| Prototype state | Ý nghĩa | App thật |
|---|---|---|
| `hosts[]` | id, name, ip, port, user, group, status, os, auth, key, tags, color | SwiftData `Host` |
| `keys[]` | id, name, type, fp, created | `SSHKey` (metadata) + Keychain item (private key) |
| `snips[]` | id, name, cmd, tags | SwiftData `Snippet` |
| `sessions{}` | sid → hostId, status, lines, cwd, hist, connectedAt | `TerminalSession` (ObservableObject) giữ SSH channel |
| `tabs[]` | id, panes[sid], dir, focus, view(term/monitor) | `WorkspaceTab` |
| `sftp` | lp, rh, rp, selL, selR, over | `SFTPBrowserModel` ×2 |
| `queue[]` | transfer items | `TransferQueue` (actor) |
| `set` | theme, fontSize, cursor, pinOn, lockMin, keepAlive, timeout | `@AppStorage` + PIN trong Keychain |
| `mon{}` | 60 điểm CPU/RAM, procs | `HostMetricsSampler` |

## Design Tokens
**Dark (mặc định)**

| Token | Giá trị |
|---|---|
| accent | `#0a84ff` |
| ok / warn / bad | `#30d158` / `#ffd60a` / `#ff453a` |
| window bg | `#1e1e1e` |
| toolbar | `#262626` |
| tab bar / active tab | `#171717` / `#1e1e1e` |
| sidebar | `rgba(40,40,42,.62)` + blur 40px saturate 180% |
| text / text2 / text3 | `rgba(255,255,255,.88 / .56 / .32)` |
| separator | `rgba(255,255,255,.08)` |
| hover / selected | `rgba(255,255,255,.07 / .11)` |
| card / card hover / card border | `rgba(255,255,255,.04 / .07 / .07)` |
| card selected | `rgba(10,132,255,.16)` |
| field | `rgba(255,255,255,.08)` |
| menu | `rgba(42,42,44,.8)` + blur 30px, border `rgba(255,255,255,.12)` |
| sheet | `#2b2b2d` |
| terminal bg / fg | `#141414` / `#e4e4e4` |
| term dim / red / green / blue | `#8a8a8e` / `#ff6b61` / `#5ad87a` / `#64a8ff` |
| window shadow | `0 30px 80px rgba(0,0,0,.55), 0 0 0 .5px rgba(0,0,0,.7)` |

**Light:**

| Token | Giá trị |
|---|---|
| accent | `#007aff` |
| ok / warn / bad | `#28b44a` / `#e6b800` / `#ff3b30` |
| window | `#ffffff` |
| toolbar | `#f6f6f6` |
| sidebar | `rgba(234,234,237,.68)` |
| text | `rgba(0,0,0,.86 / .55 / .35)` |
| terminal | `#ffffff` / `#1d1d1f` |
| term red / green / blue | `#d70015` / `#248a3d` / `#0040dd` |
| sheet | `#f2f2f4` |

**Terminal themes:**

| Theme | bg | fg | dim | red | green | blue | cursor |
|---|---|---|---|---|---|---|---|
| Shellbay | theo appearance | | | | | | accent |
| Dracula | `#282a36` | `#f8f8f2` | `#6272a4` | `#ff5555` | `#50fa7b` | `#bd93f9` | `#f8f8f2` |
| Nord | `#2e3440` | `#d8dee9` | `#616e88` | `#bf616a` | `#a3be8c` | `#81a1c1` | `#d8dee9` |
| Solarized Dark | `#002b36` | `#93a1a1` | `#586e75` | `#dc322f` | `#859900` | `#268bd2` | `#93a1a1` |

**Typography**
- **UI:** SF Pro (`-apple-system`).
  - Body 13px.
  - Small 12px.
  - Caption 11px.
  - Section title 15px/600.
  - Metric value 22px/600 (letter-spacing −0.3px).
- **Mono:** SF Mono.
  - Terminal 10–20pt.
  - Address and fingerprint 11.5px.

**Radius:** window 12 · card 10 · sheet 12 · menu 8 · field/button 6 · segmented 7/5 · row 5–6 · chip 10.

**Spacing:** content padding 20×24 · card gap 10 · section gap 16–26 · form gap 10×12.

## Assets
- **Icons:** toàn bộ là SVG nét mảnh vẽ tay mô phỏng SF Symbols. App thật nên dùng **SF Symbols**:
  - `server.rack`, `key`, `terminal`, `folder`, `arrow.left.arrow.right`, `gearshape`, `plus`, `magnifyingglass`
  - `square.split.2x1`, `square.split.1x2`, `waveform.path.ecg`, `doc.on.doc`, `trash`, `pencil`
  - `play.fill`, `lock`, `arrow.up`, `arrow.down`, `checkmark.circle`
- **Logo Ubuntu:** vòng tròn #E95420 vẽ bằng SVG. App thật nên dùng asset chính thức theo brand guideline của Canonical, hoặc icon theo OS lấy từ `/etc/os-release`.
- Prototype không có ảnh bitmap.

## Files
- `Shellbay.dc.html`: toàn bộ prototype trong một file (template + logic). Trong phần logic có sẵn dữ liệu mẫu (`SEED`, `KEYS`, `SNIPS`, `THEMES`, `SHORTCUTS`, `MON_PROCS`, `localTree`/`remoteTree`), nên tham khảo khi viết fixtures và preview.
- `support.js`: runtime cần để mở prototype trong trình duyệt. Không dùng cho app thật.
- `PLAN.md`: kế hoạch triển khai chi tiết theo từng giai đoạn.
