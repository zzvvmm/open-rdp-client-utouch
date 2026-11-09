# Unreleased

- Add a Qt 6 desktop frontend with saved PCs, reusable accounts, certificate inspection, clipboard/audio redirection, dynamic resolution, fullscreen, and optional touch controls.
- Build native amd64 `.deb` packages for Ubuntu 24.04 and Debian 13. Desktop upgrades use downloaded packages; Ubuntu Touch keeps OpenStore updates.
- Split shared implementation into `open-rdp-client/`, with Linux and Ubuntu Touch frontends in `linux/` and `ubuntu-touch/`. Ubuntu Touch package identity and saved-data locations are preserved.
- Automatically publish tested Ubuntu and Debian `.deb` packages to GitHub Releases on stable version tags, with distribution-specific filenames, checksums, source provenance, and verification of downloaded assets.

- Refresh Linux and Ubuntu Touch with a Windows App inspired PC library, shared light/dark styling, responsive cards and rows, and accessible connection actions.
- Add Recent connections, saved layout/sort preferences, group filtering and management, temporary Quick Connect, and Save & Connect with inline save failures.
- Keep connection failures visible with Retry, confirm session replacement, ignore late events from cancelled attempts, and count Recent only after successful connections.
- Fix desktop thumbnail URLs and delivery of backend action errors. Temporary sessions stay out of profile storage and thumbnail caches until explicitly saved.
- Exercise installed Qt 5/Qt 6 frontends with isolated demo data and attach desktop/mobile UI screenshots to CI artifacts.
