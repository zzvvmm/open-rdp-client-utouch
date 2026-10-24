# Open RDP Client for Ubuntu Touch (`rdp-client-ut`)

**Open RDP Client** is an open-source (**GPL-3.0-or-later**) Remote Desktop Protocol (RDP) client for **Ubuntu Touch (Lomiri)** powered by a pure-Rust **IronRDP** backend and a **QtQuick / Lomiri UI Toolkit** frontend inspired by Microsoft's **Windows App** (formerly Microsoft Remote Desktop).

The package ID remains `rdp-client-ut.zzvvmm` for compatibility with existing installations and saved data.

---

## Features

- **Windows App–Inspired Saved PCs Dashboard (`DevicesPage.qml` & `PcCard.qml`)**
  - Responsive 1- to 3-column card grid adapting from phone portrait to tablet and Lomiri Convergence external monitors.
  - Automatic 16:9 last-session PNG screenshot thumbnails (`$XDG_CACHE_HOME/rdp-client-ut.zzvvmm/thumbnails/`).
  - Search, Favorites filter, quick duplicate, and a pre-configured **Interactive Windows 11 Demo PC** (`demo.local:3389`) for instant offline testing.
- **Enterprise-Ready RDP Protocol Engine (`src/rdp/session_worker.rs`)**
  - Pure-Rust **IronRDP** (`ironrdp-connector`, `ironrdp-session`, `ironrdp-tokio`, `ironrdp-tls`) running on a dedicated `tokio` worker thread.
  - **CredSSP / NLA (Network Level Authentication)** with `DOMAIN\username` and UPN support.
  - **Trust-On-First-Use (TOFU) Certificate Verification (`CertPromptDialog.qml`)**: Inspects X.509 Common Name, Issuer, Validity dates, and SHA-256 fingerprint before sending NLA credentials, and alerts on fingerprint mismatches.
  - **Dynamic Display Resize (`DISP` DVC Channel)**: Automatically resizes the remote Windows desktop when rotating the device or resizing the window in Lomiri Convergence mode.
  - **Bidirectional Clipboard Redirection (`CLIPRDR`)**: Syncs Unicode text (`CF_UNICODETEXT` / `CF_TEXT`) between Ubuntu Touch and the remote Windows session.
  - **Audio Output Redirection (`RDPSND`)**: Streams 44.1 kHz / 48 kHz 16-bit stereo PCM audio from the remote PC to Ubuntu Touch via `QtMultimedia`.
- **Touchscreen Ergonomics Built for Mobile (`VirtualTrackpad.qml` & `VirtualKeyBar.qml`)**
  - **Mouse Pointer (Virtual Trackpad) Mode**: Relative trackpad movement with configurable speed, 1-finger tap left-click, double-tap, long-press drag selection, 2-finger tap right-click, and 2-finger scroll wheel.
  - **Direct Touch Mode**: Tap directly at remote coordinates; press-and-hold triggers right-click with a visual indicator.
  - **Pinch-to-Zoom & Pan (`RdpViewport.qml`)**: Quick `100%` / `150%` / `200%` zoom and pan.
  - **3-State Sticky Modifier & Function Key Bar (`VirtualKeyBar.qml`)**: `Ctrl`, `Alt`, `Shift`, and `Win` support `Off` → `Latched (•)` → `Locked (••)`, alongside `Esc`, `Tab`, arrow keys, `Home`/`End`/`PgUp`/`PgDn`, `F1`–`F12`, and one-tap shortcuts (`Ctrl+Alt+Del`, `Alt+Tab`, `Win+D`, `Win+L`, `Ctrl+Shift+Esc`).
- **Encrypted Local Credential Vault (`src/storage/credentials.rs`)**
  - Reusable User Accounts (`AccountsPage.qml`) with passwords sealed in `$XDG_DATA_HOME/rdp-client-ut.zzvvmm/vault.json`.

---

## Architecture

```text
rdp-client-ut/
├── Cargo.toml                  # Pure-Rust IronRDP engine & storage crate
├── CMakeLists.txt              # Builds Rust staticlib + Qt5/QML shell executable
├── clickable.yaml              # Clickable configuration for Ubuntu Touch 24.04 (Noble)
├── manifest.json.in            # Click package manifest
├── rdp-client-ut.apparmor      # AppArmor profile (networking, audio, keep-display-on)
├── rdp-client-ut.desktop.in    # Lomiri launcher entry
├── assets/                     # Suru squircle logo & vector UI icons
├── qml/
│   ├── Main.qml                # Root MainView, state dispatcher, & credential dialog
│   ├── theme/Theme.qml         # Fluent Dark & Suru Light design tokens
│   ├── pages/                  # DevicesPage, PcEditorDialog, AccountsPage, SettingsPage, SessionPage
│   └── components/             # PcCard, RdpViewport, VirtualTrackpad, SessionHudPill, VirtualKeyBar, CertPromptDialog
├── qt/                         # Thin C++/Qt5 QQuickPaintedItem (RdpCanvas) & QAudioOutput bridge
└── src/
    ├── lib.rs                  # C FFI exports for Qt bridge
    ├── app_controller.rs       # Central state & session controller
    ├── models/                 # PcProfile, UserAccount, & X.509 TOFU CertStore
    ├── storage/                # Atomic JSON storage & encrypted CredentialVault
    └── rdp/                    # SharedFrameBuffer, InputMapper, Cliprdr, Rdpsnd, & IronRDP worker
```

---

## Building & Testing

### 1. Run Rust Unit Tests
```bash
cargo test
```

### 2. Build Ubuntu Touch `.click` Package with Clickable
```bash
# Build for x86_64 (amd64 desktop / emulator)
clickable build --arch amd64

# Build for ARM64 (Ubuntu Touch phones & tablets)
clickable build --arch arm64
```

### 3. Install & Launch on an Ubuntu Touch Device over ADB
```bash
clickable install --arch arm64
clickable launch --arch arm64
```

---

## License

This project is licensed under the **GNU General Public License v3.0 or later (`GPL-3.0-or-later`)** — see [LICENSE](LICENSE) for details.
