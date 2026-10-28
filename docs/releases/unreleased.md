# Unreleased

- Fix Dynamic (Fit) showing a blank or corrupted desktop after connection or
  rotation. Wait for desktop pixels before the initial resize, preserve codec,
  compression, and fragmented-update state, and replay traffic interleaved with
  reactivation instead of discarding it. Retain the fix for `no RFX channel found`.
- Disable outer RDP bulk compression to avoid the current engine's XRDP resize
  corruption. RemoteFX graphics compression remains enabled.
- Clear pixels using the old row stride when resizing the framebuffer.
- Put **Device Native** and **Direct Touch** first in their lists and select them
  by default for new PCs. Migrate old persisted global defaults once, preserving
  other preferences and existing saved PCs' resolution/input choices.
- Add **Report Errors** in Settings, enabled by default and remembered across
  restarts. Switching it off immediately prevents new reports, including when
  saving the preference fails; storage failures are shown locally.
- Integrate separate Sentry projects for Rust backend failures and Qt/QML errors,
  with app version, environment, architecture, framework, and safe source locations.
- Capture Rust panics, unexpected RDP errors, QML reference/type/binding/load
  failures, and Qt critical messages. Expected connection failures stay local.
- Remove raw messages, credentials, PC addresses, user/account data, clipboard
  contents, screenshots, breadcrumbs, local paths, and variable values from reports.
  Repeated errors at the same source location are limited to one per minute.

The setup was verified with a caught Rust panic and a QML reference error from
the actual application initialization paths. A native QML type error triggered
with reporting disabled did not reach Sentry. Native signal crashes/minidumps
are not captured. These changes have not been released to OpenStore or GitHub.

Validation: 52 Rust tests and 68 QML checks passed. A local XRDP/Xorg session
rendered correctly through initial fit, landscape, and portrait resizes; the
synthetic terminal image was inspected and checked for a coherent pixel region.
Regression tests cover continuous compression history, fragmented graphics,
interleaved handshake traffic, startup resize readiness, framebuffer clearing,
and legacy global-default migration. Both amd64 and arm64 packages passed review.
A full native Main → Add PC check using old settings confirmed the selected
defaults, their first positions, and their rendered highlights. The corrected
arm64 package was installed and launched on the USB device: its binary checksum
matches the reviewed build, global defaults migrated to Native/Direct Touch, and
the saved-PC file's checksum was unchanged. The affected host still needs device
retesting.
