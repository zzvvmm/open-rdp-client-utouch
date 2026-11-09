# Linux desktop builds and validation

The first package targets are Ubuntu 24.04 and Debian 13 on amd64. Desktop uses Qt 6.4+; Ubuntu Touch continues to use Qt 5.15/Lomiri. The root CMake option `OPEN_RDP_PLATFORM` selects one frontend per build directory. Use current stable Rust for the checked-in dependency lockfile.

## Build and package

Follow the dependency list and commands in [README](../README.md). `linux/packaging/Dockerfile` accepts `DISTRO=ubuntu:24.04` or `DISTRO=debian:13`. Run `scripts/build-linux-ci.sh ubuntu24` or `debian13` inside its container to configure, build, run CTest under Xvfb, and generate a package.

Packages are written under `build/linux-FLAVOR/packages/`. Distribution names belong to the enclosing artifact directory: the Debian package itself remains `open-rdp-client_VERSION_amd64.deb`. CPack computes shared-library dependencies; the package also declares the runtime QML modules, SVG support, and the Qt Wayland plugin. Install the package using `apt install ./PATH.deb` so dependencies are resolved.

Desktop data lives under `open-rdp-client` in the XDG config, data, and cache directories. Upgrades retain these directories. Ubuntu Touch continues to use `rdp-client-ut.zzvvmm`. No profile or vault migration occurs between platforms.

## Automated validation

- Rust tests run with each platform feature, including a subprocess check that default XDG storage selects only that platform's directories.
- Desktop CTest checks hardware key presses/releases, focus loss, disabling input, the fullscreen chord, PC/account editors, certificate mismatch prompts, and dynamic/fixed resolution.
- Shared state and input tests run on both Qt 5 and Qt 6. Existing Lomiri regressions remain in the Ubuntu Touch suite.
- CI installs each generated `.deb` in a fresh instance of its own distribution, then launches `scripts/smoke-linux.py` under Xvfb. The app's `--smoke-test` option connects only to the offline demo, accepts its test certificate for that session, checks for a live framebuffer, and exits. The harness creates temporary XDG directories and disables error reporting.

To check an installed package on an X11 session:

```bash
QT_QPA_PLATFORM=xcb python3 scripts/smoke-linux.py
```

For a headless X11 check:

```bash
xvfb-run -a env QT_QUICK_BACKEND=software python3 scripts/smoke-linux.py
```

For a native Wayland session:

```bash
QT_QPA_PLATFORM=wayland python3 scripts/smoke-linux.py
```

Capture the PC library and connected demo with deterministic sample PCs:

```bash
xvfb-run -a env QT_QUICK_BACKEND=software python3 scripts/smoke-linux.py \
  --theme light --layout list --size 1100x760 --library-fixture \
  --snapshot-prefix build/ui/linux/light-list
```

The harness accepts `--executable` for an uninstalled build. Ubuntu Touch uses
`--platform ubuntu-touch --executable build/x86_64-linux-gnu/app/install/rdp-client-ut`;
run it inside Clickable with Xvfb/Mesa, as `clickable test` does. A prefix produces
`-dashboard.png` and `-session.png` files. Use `--font-scale 1.5` to exercise
larger application fonts independently of display scaling. CI attaches these screenshots separately
from release package artifacts.

The demo checks startup, imports, resources, painting, and application/backend integration. It does not establish real-server interoperability or validate sound and clipboard exchange with other applications.

## Interactive acceptance checks

Before release, record the distribution, desktop environment, display protocol, server, and whether a physical Ubuntu Touch device was used.

1. Create, edit, search, favorite, duplicate, and delete PCs. Check Recent, sorting, layout persistence, combined group/search filters, and group rename/removal. Try Quick Connect, save a temporary PC, reject invalid saves, and use Save & Connect. Reopen the application and verify persistence and thumbnails.
2. Add and edit accounts, retain a password when editing with a blank password, connect using saved credentials, and exercise the ask-every-time dialog. Confirm password fields clear after use.
3. Connect to Windows and xrdp using NLA. Check trust-once, trust-always, rejection, certificate changes, and revocation. Credentials must not be sent before certificate approval.
4. Check physical keyboard input, held modifiers, Escape, Tab, shortcuts, mouse buttons, dragging, and scrolling. Open a dialog, switch applications, and end a session while input is held; no remote key or button should remain held.
5. Toggle fullscreen with Ctrl+Alt+Enter, return to PCs, resume the session, and disconnect. Check direct touch, virtual trackpad, zoom, precision controls, drag lock, and virtual keys where input devices are available.
6. Resize on X11 and Wayland, including display scaling. Dynamic profiles follow the available viewport; native profiles use the initial viewport; fixed profiles preserve their resolution.
7. Exchange Unicode clipboard text in both directions with another application. Verify local and remote audio modes, disabled audio, and an absent local audio device.
8. Verify Ubuntu Touch portrait/landscape, on-screen keyboard behavior, pointer controls, saved data, and OpenStore update checks after shared changes.

## Automated GitHub releases

PRs and pushes to `main` build and test both distribution packages. Pushing a stable `vX.Y.Z` tag additionally publishes those exact tested `.deb` files after Rust, Ubuntu Touch, and Linux checks pass. Prepare matching versions with `scripts/release-version.py` and finalize `docs/releases/X.Y.Z.md` before tagging.

Downloads are named `open-rdp-client_X.Y.Z_ubuntu24_amd64.deb` and `open-rdp-client_X.Y.Z_debian13_amd64.deb`. Renaming the downloads leaves the internal Debian package name/version unchanged. `SHA256SUMS-linux` and `LINUX_RELEASE_COMMIT` record the checksums and source revision.

The publishing job uses the repository's built-in `GITHUB_TOKEN`. It creates a GitHub Release when needed or attaches missing assets to an existing release, preserving its notes and publication state. Identical existing assets are skipped; conflicting bytes stop publication. Uploads are downloaded again for verification. Retry only the failed publication job to reuse its original build artifacts. See [RELEASING.md](RELEASING.md) for the complete process.

Desktop users continue to install `.deb` upgrades manually. OpenStore publication and APT repository hosting remain separate workflows.

## Validation recorded for the library upgrade

- Rust: 59 unit tests and the storage-isolation integration test pass with each platform feature. Conflicting platform features are rejected.
- Qt 6: all three CTest suites pass on Ubuntu 24.04 (Qt 6.4.2) and Debian 13 (Qt 6.8.2). Each run reports five native-input checks, 15 desktop workflow/window checks, and 16 shared checks, including Quick Connect, rejected saves, Save & Connect, certificate prompts, and fullscreen.
- Qt 5: 79 Lomiri QML checks plus 16 shared checks pass. Native amd64 demo checks cover light/dark portrait, compact landscape, list layout, and enlarged text under Xvfb/Mesa.
- Packages: Ubuntu and Debian amd64 `.deb` files install and render the offline demo in fresh runtime containers with only declared runtime dependencies and test tools. Ubuntu Touch amd64 and arm64 `.click` packages both pass Clickable review.
- Rendering: the desktop demo renders with X11/OpenGL under Xvfb/Mesa and through the Wayland platform plugin under nested Weston with an input seat. These are virtual display environments.
- Real Windows/xrdp server connections, clipboard/audio exchange with external applications, and physical Ubuntu Touch hardware remain unverified for this upgrade. These checks still require release-time validation with a real server and device.
