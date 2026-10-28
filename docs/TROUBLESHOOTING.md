# Connection troubleshooting

## PC addresses and saved names

`hostname-01` is a valid PC hostname. The app accepts names, IPv4 addresses,
and IPv6 addresses, with an optional RDP port:

| Example | Meaning |
| --- | --- |
| `hostname-01` | Resolve using the phone's system DNS, port 3389 |
| `hostname-01.home.example:3390` | Full DNS name, custom port |
| `192.168.1.50` | LAN IPv4 address, port 3389 |
| `[fd00::1234]:3390` | IPv6 address, custom port |
| `fd00::1234` | IPv6 address, port 3389 |

The Friendly Name is only a display label. Changing it does not change the PC
address used for the connection. Open **Edit Remote PC** and check the **PC Name**
field if a saved address looks incomplete. Re-enter the original address and
save; a suffix lost in an earlier save cannot be recovered automatically.

The pending hostname fix disables predictive text and automatic capitalization
for that field, and commits keyboard composition before saving. The current
public v0.2.0 release does not contain that fix. Until a fixed release is
available, dismiss the keyboard and verify the full address before saving, or
try the PC's LAN IP address.

## WireGuard or another VPN

The app uses system DNS and routing. It does not configure or start a VPN.
Connect the VPN on Ubuntu Touch before opening the remote PC.

1. Try the PC's **LAN IP address** through the VPN. Use the same RDP port that
   works at home. This separates name resolution from reaching the PC.
2. If the IP works but the hostname does not, check VPN DNS. A short name or
   `.local` name that works at home may depend on local discovery that does not
   cross a routed VPN. Try the full name served by your home/VPN DNS.
3. If the IP also fails, check that the WireGuard peer's `AllowedIPs` and the
   system route include the PC's LAN subnet. Check router forwarding and the
   return route from the LAN to the VPN client subnet. If the network you are
   visiting uses the same LAN subnet as home, overlapping routes can send the
   connection to the wrong network.
4. Check that the PC is awake, RDP is listening, and its firewall allows the RDP
   port from the VPN client subnet. The default is TCP 3389; custom installations
   can use a different port. WireGuard transports the RDP connection within its
   tunnel; the router's WireGuard endpoint port is not the PC's RDP port.
5. If TCP connects but negotiation or TLS stalls, investigate tunnel MTU and
   packet filtering. Use a value appropriate to the actual tunnel path rather
   than changing the app's security settings.
6. For domain accounts, the domain controller and DNS must also be reachable
   through the VPN. A successful TCP connection to the PC alone does not prove
   that domain authentication will work.

The pending fixes improve IPv4/IPv6 fallback, cancel stalled connections, and
remove a loopback-only binding in Kerberos UDP authentication. These address
specific app defects; they do not establish the cause of every VPN failure.
The reporter's WireGuard setup has not been reproduced yet.

## Dynamic (Fit): no RFX channel found

This error concerns the RemoteFX graphics codec's saved channel state. A display
resize can trigger RDP deactivation/reactivation. The pending fix preserves codec
headers, compression history, and fragmented graphics during that sequence, and
updates frame acknowledgement parameters. It queues interleaved frames instead
of dropping them while reading activation messages.

A blank or corrupted screen can also occur without a connection error. The
client now waits for desktop pixels before the first DISP request, clears the
resized framebuffer, and disables outer RDP bulk compression to avoid corruption
seen with the current engine and XRDP. RemoteFX graphics compression stays on.

Until a build containing the fix is installed, edit the PC and select **Device
Native** or a fixed resolution, then reconnect. Device Native becomes the default
for new PCs; existing saved Dynamic (Fit) selections remain available.

The regression test decodes RemoteFX tile updates across portrait/landscape
reactivations, with and without bulk compression. This reproduces the old error
when the graphics processor is replaced, and verifies updated frame
acknowledgements and continued keyboard input with the fix. A local XRDP/Xorg
session also passed three live resizes with a coherent synthetic terminal image.
The affected host still needs device retesting before release.

On upgrade, old global Dynamic/Mouse Pointer defaults migrate once to Device
Native/Direct Touch. Open **Add PC** to see those defaults selected as the first
options. Editing an existing PC retains that PC's saved selections.

Related report: [OPEN-RDP-CLIENT-UTOUCH-BACKEND-2](https://dd-0q.sentry.io/issues/7816583170/).

## Information to include in a report

- App version, Ubuntu Touch version, and device model.
- The exact connection error and the stage where it stops: resolving, TCP,
  negotiation, TLS, or authentication.
- Whether the connection works on the home network and whether the PC's LAN
  IP works through the VPN. Say whether the saved PC uses a short name, a full
  DNS name, IPv4, or IPv6; private names can be redacted.
- Whether it is a local Windows account or a domain account, and the last app
  version that worked if known.

Share the error text or a cropped screenshot without passwords or private
keys. No account credentials or full WireGuard configuration are needed.

## References

- [Qt input method hints](https://doc.qt.io/qt-6/qt.html#InputMethodHint-enum)
  and [committing keyboard composition](https://doc.qt.io/qt-6/qinputmethod.html#commit).
- [Tokio TCP address attempts](https://docs.rs/tokio/latest/tokio/net/struct.TcpStream.html#method.connect).
- [WireGuard routing overview](https://www.wireguard.com/#cryptokey-routing).
