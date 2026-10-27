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
