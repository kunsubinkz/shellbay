# Shellbay

Shellbay là SSH client native cho macOS (SwiftUI + [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)), giao diện dark mode mặc định, có light mode.

## Tính năng

- **Hosts**: danh sách host dạng card/list, nhóm theo folder, tìm kiếm, thêm/sửa/nhân bản/xóa host.
- **Terminal**: nhiều tab, chia pane ngang/dọc, theme terminal (Shellbay, Dracula, Nord, Solarized Dark).
- **Monitor**: CPU/RAM/Disk/Uptime, biểu đồ realtime và top process của host đang kết nối.
- **Keychain**: tạo/nhập SSH key, copy public key; private key lưu trong macOS Keychain.
- **SFTP**: duyệt file Local/Remote, hàng đợi truyền file.
- **Snippets**: lệnh lưu sẵn, chạy trên host đã chọn.
- **Settings**: theme, font, con trỏ, khóa PIN, keep-alive/timeout.

Kết nối SSH dùng `ssh` có sẵn của macOS (`/usr/bin/ssh`), nên không cần cài thêm thư viện SSH.

## Yêu cầu

- macOS 14 (Sonoma) trở lên
- Xcode 15.3+ hoặc Command Line Tools (Swift 5.10+)

```bash
xcode-select --install   # nếu chưa có toolchain
```

## Build

Toàn bộ mã nguồn nằm trong thư mục [`app/`](app/) (Swift Package, dependency được tải tự động qua SwiftPM).

```bash
cd app
./scripts/bundle.sh            # build debug  -> dist/Shellbay.app (ad-hoc signed)
./scripts/bundle.sh release    # build release -> dist/Shellbay.app
open dist/Shellbay.app
```

Đóng gói file cài đặt `.dmg` (build release rồi tạo `dist/Shellbay-<version>.dmg` với layout kéo-thả vào Applications):

```bash
cd app
./scripts/make-dmg.sh
```

Chạy nhanh khi phát triển, không cần đóng gói `.app`:

```bash
cd app
swift run Shellbay
```

> App được ký ad-hoc, chưa notarize. Lần đầu mở bản tải từ nơi khác, macOS có thể chặn: chuột phải vào `Shellbay.app` → **Open**, hoặc chạy `xattr -dr com.apple.quarantine dist/Shellbay.app`.

## Test

```bash
cd app
swift test
```

Các unit test chạy mặc định. Test E2E với SSH thật sẽ tự bỏ qua trừ khi đặt biến môi trường:

| Biến | Ý nghĩa |
|---|---|
| `SB_E2E_KEY` | Đường dẫn private key được phép đăng nhập vào user `ubuntu` |

Cần một sshd chạy tại `127.0.0.1:2222` với user `ubuntu` (ví dụ container `ubuntu:24.04` cài openssh-server).

## Biến môi trường cho phát triển

| Biến | Tác dụng |
|---|---|
| `SHELLBAY_DATA=<file>` | Lưu dữ liệu vào file chỉ định, tránh đụng dữ liệu thật |
| `SHELLBAY_SNAPSHOT=<dir>` | Render từng màn hình ra PNG rồi thoát |

## Cấu trúc thư mục

```
.
├─ app/                      Swift Package của ứng dụng
│  ├─ Package.swift
│  ├─ Sources/ShellbayCore/  Model, validator, parser, Keychain, SSH/transfer, PIN
│  ├─ Sources/Shellbay/      Giao diện SwiftUI
│  ├─ Tests/ShellbayTests/   Unit test + E2E
│  ├─ Resources/             Icon 1024px
│  ├─ scripts/               bundle.sh, make-dmg.sh
│  └─ dist/                  Kết quả build (.app, .dmg)
├─ DESIGN.md                 Đặc tả thiết kế UI (handoff từ prototype)
├─ PLAN.md                   Kế hoạch triển khai theo giai đoạn
├─ Shellbay.dc.html          Prototype HTML tham chiếu
└─ support.js                Runtime để mở prototype
```

## Phím tắt chính

| Phím | Hành động |
|---|---|
| `⌘N` | New Host |
| `⌘T` / `⌘W` | New Tab / Close Tab |
| `⌘O` / `⌘E` / `⌘D` / `⌘⌫` | Connect / Edit / Duplicate / Delete host đang chọn |
| `⌘D` / `⇧⌘D` | Split Right / Split Down (trong terminal) |
| `⌘1` / `⌘2` | Terminal / Monitor |
| `⌘,` | Settings |
| `⌃⌘L` | Khóa Shellbay |

## Prototype thiết kế

Để xem prototype HTML, đặt `Shellbay.dc.html` và `support.js` cùng thư mục rồi chạy static server:

```bash
python3 -m http.server
```

Chi tiết spec UI xem [DESIGN.md](DESIGN.md), kế hoạch triển khai xem [PLAN.md](PLAN.md).
