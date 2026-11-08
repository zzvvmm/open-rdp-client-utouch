# Open RDP Client

Open RDP Client is a GPL-3.0-or-later remote desktop client powered by the pure-Rust **IronRDP** engine. It provides a **Qt 6 / Qt Quick Controls frontend for Linux desktop** and a **Qt 5.15 / Lomiri frontend for Ubuntu Touch**.

Both frontends support saved PCs, search and favorites, reusable accounts, NLA/CredSSP authentication, certificate inspection and trust-on-first-use, screenshots, clipboard text synchronization, PCM audio, resolution presets, dynamic display resize, and an interactive offline demo. Each application supports one active session.

## Repository structure

```text
root/
├── CMakeLists.txt          # Selects Linux or Ubuntu Touch
├── Cargo.toml             # Shared Rust workspace; one Cargo.lock
├── open-rdp-client/
│   ├── src/               # IronRDP, controller, storage, models, C FFI
│   ├── qt/                # Shared Qt bridge, canvas, Qt 5/6 audio
│   ├── qml/OpenRdp/       # Shared state, viewport, pointer and keyboard logic
│   ├── assets/            # Logo, icons, existing screenshots
│   └── tests/
├── linux/                 # Qt 6 frontend, native input, tests, DEB packaging
├── ubuntu-touch/          # Qt 5/Lomiri frontend, translations, Click packaging
├── vendor/                # IronRDP session patch
├── scripts/
├── docs/
└── .github/
```

## Build Linux desktop

Initial binary targets are **Ubuntu 24.04 and Debian 13, amd64**. Build on the distribution you intend to package for. Qt 6.4 or later and Rust 1.89 or later are required; the locked dependencies may require a newer stable Rust compiler.

Install a current stable Rust toolchain using [rustup](https://rustup.rs/), then install the build and runtime dependencies:

```bash
sudo apt update
sudo apt install build-essential cmake ninja-build python3 pkg-config zlib1g-dev \
  qt6-base-dev qt6-declarative-dev qt6-multimedia-dev qt6-svg-dev qt6-wayland \
  qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-layouts \
  qml6-module-qtquick-templates qml6-module-qtquick-window \
  qml6-module-qtqml-workerscript qml6-module-qttest xvfb xauth file dpkg-dev
cmake -S . -B build/linux -DOPEN_RDP_PLATFORM=linux -DCMAKE_BUILD_TYPE=Release
cmake --build build/linux
xvfb-run -a ctest --test-dir build/linux --output-on-failure
cpack --config build/linux/CPackConfig.cmake -G DEB
```

On Debian 13, also install `qt6-svg-plugins` for SVG icons (`sudo apt install qt6-svg-plugins`). Ubuntu 24.04 includes that plugin in `libqt6svg6`.

Run `build/linux/linux/open-rdp-client`, or install the generated package with `sudo apt install ./build/linux/packages/open-rdp-client_0.3.0_amd64.deb`. Package versions follow the shared application version. To install without packaging, use `cmake --install build/linux --prefix ~/.local`.

On a graphical Linux session, `ctest --test-dir build/linux --output-on-failure` can run directly. To build without test dependencies, configure with `-DBUILD_TESTING=OFF`.

For an isolated distribution build, use the provided container recipe:

```bash
docker build -f linux/packaging/Dockerfile --build-arg DISTRO=ubuntu:24.04 -t open-rdp-build:ubuntu24 .
docker run --rm -v "$PWD:/work" open-rdp-build:ubuntu24 sh scripts/build-linux-ci.sh ubuntu24
```

Use `DISTRO=debian:13` and a different output name to build Debian packages. These are separate artifacts built against each distribution's Qt and libc.

## Build Ubuntu Touch

Run these commands **from the repository root**. The platform configuration selects Qt 5.15 and the `ubuntu-touch-24.04-1.x` framework:

```bash
clickable build --config ubuntu-touch/clickable.yaml --arch amd64
clickable test --config ubuntu-touch/clickable.yaml --arch amd64
clickable build --config ubuntu-touch/clickable.yaml --arch arm64
clickable install --config ubuntu-touch/clickable.yaml --arch arm64
clickable launch --config ubuntu-touch/clickable.yaml --arch arm64
```

The package ID remains `rdp-client-ut.zzvvmm`, and existing PCs, accounts, certificates, settings, and thumbnails keep their existing locations. Local builds use architecture-specific CMake and Cargo output directories.

## Desktop controls

- Use a physical mouse for absolute positioning, all three buttons, dragging, and scrolling. Hardware keys retain matching press and release events.
- Use **Ctrl+Alt+Enter** or the toolbar to toggle fullscreen. Escape is sent to the remote desktop. The shortcut menu can send the fullscreen chord to the remote PC too.
- **PCs** returns to the dashboard while the session stays connected. **Disconnect** ends the session.
- Select **Touch** for direct touch or virtual trackpad controls, precision movement, drag lock, the software keyboard, sticky modifiers, navigation keys, and F1–F12.
- Dynamic resolution follows the available viewport after resizing the window. Fixed-resolution profiles retain their selected size. Native resolution is selected at connection time.
- Desktop updates are manual: open **Settings → Open releases**, download the appropriate `.deb`, and install it. Ubuntu Touch retains its OpenStore update checks.

Desktop storage uses `$XDG_CONFIG_HOME/open-rdp-client`, `$XDG_DATA_HOME/open-rdp-client`, and `$XDG_CACHE_HOME/open-rdp-client`, with standard XDG defaults. Ubuntu Touch uses the corresponding `rdp-client-ut.zzvvmm` directories. The applications do not migrate or share data automatically.

## Tests and development

```bash
cargo test --locked --workspace
cargo test --locked --workspace --no-default-features --features ubuntu-touch
python3 scripts/release-version.py --check
git diff --check
```

`linux-desktop` is the default Cargo feature. Ubuntu Touch builds disable defaults and select `ubuntu-touch`; selecting both is rejected. The Rust crate name and C FFI signatures are retained.

CMake defaults to the Linux frontend; use separate build directories for each platform. Shared QML tests run on both Qt versions. Desktop CTest covers keyboard focus/release behavior, editors, certificate prompts, and dynamic/fixed resolution. `scripts/smoke-linux.py` launches the installed application with isolated data and checks an offline demo frame; it does not validate a real RDP server.

Before release, verify real Windows/xrdp authentication, certificate decisions, clipboard, audio, and resize; check native X11 and Wayland sessions, and Ubuntu Touch hardware after shared changes. See [desktop validation](docs/LINUX.md), [development and releases](docs/RELEASING.md), [connection troubleshooting](docs/TROUBLESHOOTING.md), and [error reporting](docs/ERROR_REPORTING.md).

## License

[GNU General Public License v3.0 or later](LICENSE).
