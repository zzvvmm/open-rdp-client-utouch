# Unreleased

## Features

- Added automatic OpenStore update checks, enabled by default, with a daily
  check on opening/resuming the app and a persistent Settings toggle.
- Added a manual **Check for updates** action in **Settings → Updates**, with
  checking, up-to-date, and error feedback.
- Added a changelog popup with **Update Now**, **Update Later**, and **Skip This
  Version**. Update Now opens OpenStore for installation; Later reminds at the
  next due check, and Skip suppresses that version across app restarts.
- Manual checks can show a previously skipped version. Checks select stable
  releases compatible with the device's architecture and installed framework,
  and prompts wait until the app is active and outside remote sessions.

## Development workflow

- Added a development and release guide covering GitHub and OpenStore.
- Added the reusable `rdp-client-release` skill with release-readiness checks,
  release-note preparation, tagging, and partial-release recovery.
- Added helpers to keep all six application version fields consistent and
  verify both public OpenStore downloads against local release packages.

Choose the next version and finalize its release notes when preparing a release
candidate.
