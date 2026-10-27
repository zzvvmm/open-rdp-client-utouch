# Unreleased

- Make Direct Touch the default for new PCs and missing input-mode preferences;
  preserve explicitly saved Trackpad choices.
- Keep the virtual key bar visible above the software keyboard in portrait and
  landscape, and release held pointer buttons when the session view changes size.
- Keep the authenticated connection during rotation. Wait for the display-control
  channel and its capabilities before sending the latest resize request; fit the
  existing desktop locally when remote resizing is unsupported. Fixed-resolution
  profiles retain their selected size, and resize requests preserve display scale.
- Restore negotiated bulk decompression after in-place desktop reactivation so
  compressed screen updates remain readable following a server resize.
- Disable keyboard prediction and automatic capitalization in the PC address
  field, and commit pending keyboard input before saving, to prevent address
  rewriting or lost suffixes such as `-01`.
- Preserve IPv6 addresses and custom ports when creating saved PCs.
- Resolve names separately from TCP connection attempts and stagger attempts
  across IPv4/IPv6 addresses so a stalled route does not block a working address.
- Let Kerberos UDP authentication use the system's LAN/VPN route and support
  IPv6 domain controllers, instead of binding requests to loopback. Bound each
  UDP exchange and accept replies only from the selected domain controller.
- Report DNS, TCP, and handshake failures separately with troubleshooting hints;
  bound stalled negotiation, TLS, and authentication stages. Cancel pending
  connections when leaving the session screen.
- Add hostname editing/persistence, address fallback, cancellation, and domain
  authentication transport regression checks, plus a connection troubleshooting
  guide.

The earlier address/VPN fixes passed 28 Rust tests, 58 QML checks, and package
review for both architectures. The IPv6-saving and Kerberos UDP regression tests
also failed against the old implementations in an isolated source copy.

The touch/rotation changes pass 32 Rust tests and 65 QML checks. Both amd64 and
arm64 packages built and passed Clickable review. Resize tests
exercise real protocol encoding with simulated channel setup/capabilities; QML
session layout tests use a canvas stub. A native full-app demo stayed connected
through portrait, landscape, reduced keyboard space, and a return to portrait,
with the key bar visible throughout. A local xrdp connection authenticated but
failed with a display-decoder error before rotation; it did not validate live
server rotation. A physical-device rotation test against a real RDP server is
still needed.

These changes are not published yet. The reported WireGuard setup and Ubuntu
Touch software keyboard still need validation on a physical device; local
transport checks do not prove a complete RDP/domain login or VPN session.
