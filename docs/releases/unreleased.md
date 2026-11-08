# Unreleased

- Add a Qt 6 desktop frontend with saved PCs, reusable accounts, certificate inspection, clipboard/audio redirection, dynamic resolution, fullscreen, and optional touch controls.
- Build native amd64 `.deb` packages for Ubuntu 24.04 and Debian 13. Desktop upgrades use downloaded packages; Ubuntu Touch keeps OpenStore updates.
- Split shared implementation into `open-rdp-client/`, with Linux and Ubuntu Touch frontends in `linux/` and `ubuntu-touch/`. Ubuntu Touch package identity and saved-data locations are preserved.
