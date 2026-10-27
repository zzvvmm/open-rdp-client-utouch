# Unreleased

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

Validation: 28 Rust tests passed, including Linux SDK tests with normal container
networking; 58 QML checks passed. Both amd64 and arm64 packages built and passed
Clickable review. The IPv6-saving and Kerberos UDP regression tests also failed
against the old implementations in an isolated source copy.

These changes are not published yet. The reported WireGuard setup and Ubuntu
Touch software keyboard still need validation on a physical device; local
transport checks do not prove a complete RDP/domain login or VPN session.
