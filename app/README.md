# Shellbay (macOS)

SwiftUI + SwiftTerm SSH client built from `../DESIGN.md` / `../PLAN.md`.

```bash
./scripts/bundle.sh          # builds dist/Shellbay.app (ad-hoc signed)
open dist/Shellbay.app
swift test                   # unit tests (+ real-SSH E2E tests when SB_E2E_KEY is set)
```

E2E tests need an sshd on `127.0.0.1:2222` with user `ubuntu` (e.g. an `ubuntu:24.04` container with openssh-server)
and `SB_E2E_KEY=<path to the private key authorised for that user>`.

Layout: `Sources/ShellbayCore` (models, validators, parsers, keychain, ssh/transfer, PIN) · `Sources/Shellbay` (SwiftUI app).
Dev helper: `SHELLBAY_SNAPSHOT=<dir>` renders every screen to PNG and quits (use `SHELLBAY_DATA=<file>` to avoid touching real data).
