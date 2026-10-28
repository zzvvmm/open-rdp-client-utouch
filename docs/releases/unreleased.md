# Unreleased

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

Validation: 43 Rust tests and 66 QML checks passed. Both amd64 and arm64 Clickable
packages built successfully and passed package review. Physical-device testing
is still needed before publishing.
