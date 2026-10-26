# Open RDP Client for Ubuntu Touch (`rdp-client-ut`)

**Open RDP Client** is an open-source (**GPL-3.0-or-later**) Remote Desktop Protocol (RDP) client for **Ubuntu Touch (Lomiri)** powered by a pure-Rust **IronRDP** backend and a **QtQuick / Lomiri UI Toolkit** frontend inspired by Microsoft's **Windows App** (formerly Microsoft Remote Desktop).

The package ID remains `rdp-client-ut.zzvvmm` for compatibility with existing installations and saved data.

For the development workflow, version bumps, and releases to GitHub and OpenStore,
see the [development and release guide](docs/RELEASING.md).

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
  - **Direct Touch Mode**: Tap directly at remote coordinates, drag to move windows or select text, and press-and-hold to right-click with a visual indicator.
  - **Explicit Mouse Controls**: Dedicated left-click, right-click, double-click, drag lock, and precision pointer controls. Gesture cancellation releases held buttons.
  - **Zoom & Cursor-Following Pan (`RdpViewport.qml`)**: Quick `100%` / `150%` / `200%` zoom; in trackpad mode the viewport follows the pointer without stealing remote drag gestures.
  - **Hardware Mouse & Keyboard**: Absolute mouse positioning, all three mouse buttons, dragging, wheel input, and hardware keyboard shortcuts. Navigation keys are sent with matching releases.
  - **3-State Sticky Modifier & Function Key Bar (`VirtualKeyBar.qml`)**: `Ctrl`, `Alt`, `Shift`, and `Win` support `Off` → `Latched (•)` → `Locked (••)`, alongside `Esc`, `Tab`, arrow keys, `Home`/`End`/`PgUp`/`PgDn`, `F1`–`F12`, and one-tap shortcuts (`Ctrl+Alt+Del`, `Alt+Tab`, `Win+D`, `Win+L`, `Ctrl+Shift+Esc`).
- **Encrypted Local Credential Vault (`src/storage/credentials.rs`)**
  - Reusable User Accounts (`AccountsPage.qml`) with passwords sealed in `$XDG_DATA_HOME/rdp-client-ut.zzvvmm/vault.json`.
- **Update Checks (`Settings → Updates`)**
  - Automatic OpenStore checks are enabled by default and run at most once a day when opening or resuming the app, outside remote sessions and dialogs.
  - **Check for updates** works even with automatic checks disabled and shows skipped updates when explicitly requested.
  - Available updates show their changelog with **Update Now**, **Update Later**, and **Skip This Version**. Update Now opens the app in OpenStore for installation; Later reminds at the next scheduled check, while Skip remembers that specific version across restarts.
  - Only stable releases for the installed architecture and framework are offered. Offline automatic checks stay quiet; manual check results appear in Settings.

---

## Remote Desktop Controls

These controls work with Windows and Linux desktops, including Ubuntu/XFCE:

- **Trackpad:** Swipe one finger to move the pointer; tap to click; tap twice to double-click. Hold one finger still, then move it to drag, and lift to release. Tap with two fingers to right-click, or move two fingers to scroll.
- **Small targets:** Enable **Precise** for 35% pointer movement, then use **Left**, **Right**, or **Double** to click without disturbing the pointer.
- **Move windows or select text:** Position the pointer on the title bar or selection start, tap **Drag**, and swipe as many times as needed. Tap **Release** to drop. The held button is also released when leaving the session or switching input modes.
- **Direct touch:** Tap the target to click, drag a finger to move a window or select text, and hold still to open its context menu. Touches in the black border are ignored.
- **Zoom:** Use the floating session menu to switch between 100%, 150%, and 200%. In trackpad mode, move the pointer towards an edge to reveal that part of the desktop. Use 100% to return to the full desktop.
- **On-screen keyboard:** Hidden by default. Tap either keyboard button to open or hide it without hiding the extra key bar. After dismissing it, pointer actions and shortcuts do not reopen it. Leaving the session or backgrounding the app also hides it; returning does not reopen it automatically.
- **Typing and shortcuts:** A hardware keyboard works without opening the on-screen keyboard. The **Shortcuts** menu includes Copy/Paste/Select all, `Ctrl+Alt+T`, `Alt+F2`, `Alt+F4`, `Ctrl+Alt+D`, and terminal-friendly `Ctrl+Shift+C` / `Ctrl+Shift+V`. Their effects depend on the remote desktop's configured key bindings. The same combinations can be sent from a hardware keyboard when delivered to the app.

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

After an amd64 build, run the touch, mouse, and keyboard regression tests:

```bash
clickable test --arch amd64
```

The amd64 CI build runs these QML tests automatically.

### 3. Install & Launch on an Ubuntu Touch Device over ADB
```bash
clickable install --arch arm64
clickable launch --arch arm64
```

---

## License

This project is licensed under the **GNU General Public License v3.0 or later (`GPL-3.0-or-later`)** — see [LICENSE](LICENSE) for details.
