//! Resolve through the system (including VPN DNS) and race TCP destinations.
//! No interface binding: the operating system retains control of VPN routing.

use std::collections::VecDeque;
use std::future::Future;
use std::io;
use std::net::{IpAddr, SocketAddr};
use std::time::Duration;

use tokio::net::{lookup_host, TcpStream};
use tokio::task::JoinSet;

const DNS_TIMEOUT: Duration = Duration::from_secs(10);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(12);
const ATTEMPT_DELAY: Duration = Duration::from_millis(250);

pub(super) async fn resolve(host: &str, port: u16) -> Result<Vec<SocketAddr>, String> {
    if let Ok(ip) = host.parse::<IpAddr>() {
        return Ok(vec![SocketAddr::new(ip, port)]);
    }
    let addresses = tokio::time::timeout(DNS_TIMEOUT, lookup_host((host, port)))
        .await
        .map_err(|_| format!("DNS lookup for '{host}' timed out. Check DNS, including VPN DNS if connected, or try the PC's LAN IP address."))?
        .map_err(|e| format!("Could not resolve '{host}': {e}. Check the hostname and DNS, or try the PC's LAN IP address (short names may only work on the home network)."))?
        .collect::<Vec<_>>();
    if addresses.is_empty() {
        return Err(format!(
            "DNS returned no addresses for '{host}'. Check DNS or try the PC's LAN IP address."
        ));
    }
    Ok(interleave_addresses(addresses))
}

// Keep the resolver's preferred family first, then alternate so an unreachable
// IPv6 route (or several stale IPv4 records) cannot starve the other family.
fn interleave_addresses(addresses: Vec<SocketAddr>) -> Vec<SocketAddr> {
    let prefer_v6 = addresses.first().is_some_and(SocketAddr::is_ipv6);
    let mut preferred = VecDeque::new();
    let mut other = VecDeque::new();
    for address in addresses {
        let family = if address.is_ipv6() == prefer_v6 {
            &mut preferred
        } else {
            &mut other
        };
        if !family.contains(&address) {
            family.push_back(address);
        }
    }
    let mut ordered = Vec::new();
    while !preferred.is_empty() || !other.is_empty() {
        if let Some(address) = preferred.pop_front() {
            ordered.push(address);
        }
        if let Some(address) = other.pop_front() {
            ordered.push(address);
        }
    }
    ordered
}

pub(super) async fn connect(addresses: Vec<SocketAddr>) -> Result<TcpStream, String> {
    race_addresses(addresses, ATTEMPT_DELAY, CONNECT_TIMEOUT, |address| {
        TcpStream::connect(address)
    })
    .await
    .map_err(|e| format!("TCP connection failed: {e}. Check that the PC is online and RDP is enabled. Over VPN, check the route/AllowedIPs to the PC's LAN subnet and the firewall's RDP port rule for VPN clients."))
}

async fn race_addresses<T, F, Fut>(
    addresses: Vec<SocketAddr>,
    delay: Duration,
    timeout: Duration,
    dial: F,
) -> io::Result<T>
where
    T: Send + 'static,
    F: Fn(SocketAddr) -> Fut,
    Fut: Future<Output = io::Result<T>> + Send + 'static,
{
    if addresses.is_empty() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "no resolved addresses",
        ));
    }
    let destinations = addresses
        .iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .join(", ");
    let mut attempts = JoinSet::new();
    for (index, address) in addresses.into_iter().enumerate() {
        let attempt = dial(address);
        attempts.spawn(async move {
            tokio::time::sleep(delay.saturating_mul(index as u32)).await;
            attempt
                .await
                .map_err(|e| io::Error::new(e.kind(), format!("{address}: {e}")))
        });
    }
    // Dropping JoinSet aborts pending sockets on success, timeout, or cancellation.
    tokio::time::timeout(timeout, async {
        let mut last_error = io::Error::other("all connection attempts failed");
        while let Some(result) = attempts.join_next().await {
            match result {
                Ok(Ok(stream)) => return Ok(stream),
                Ok(Err(error)) => last_error = error,
                Err(error) => last_error = io::Error::other(error),
            }
        }
        Err(last_error)
    })
    .await
    .map_err(|_| {
        io::Error::new(
            io::ErrorKind::TimedOut,
            format!("timed out reaching {destinations}"),
        )
    })?
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::net::TcpListener;

    fn addresses() -> Vec<SocketAddr> {
        [
            "[2001:db8::1]:3389",
            "[2001:db8::2]:3389",
            "10.0.0.2:3389",
            "10.0.0.3:3389",
        ]
        .map(|value| value.parse().unwrap())
        .to_vec()
    }

    #[test]
    fn alternates_families_without_losing_resolver_preference_or_ports() {
        let addresses = addresses();
        assert_eq!(
            interleave_addresses(addresses.clone()),
            vec![addresses[0], addresses[2], addresses[1], addresses[3]]
        );
        assert_eq!(
            interleave_addresses(vec![addresses[2], addresses[0], addresses[3], addresses[2]]),
            vec![addresses[2], addresses[0], addresses[3]]
        );
    }

    #[tokio::test]
    async fn stalled_first_address_does_not_block_fallback() {
        for stalled_v6 in [true, false] {
            let mut addresses = interleave_addresses(addresses());
            if !stalled_v6 {
                addresses.swap(0, 1);
            }
            let stalled = addresses[0];
            let reachable = addresses[1];
            let result = race_addresses(
                addresses,
                Duration::from_millis(5),
                Duration::from_millis(200),
                move |address| async move {
                    if address == stalled {
                        std::future::pending::<()>().await;
                    }
                    if address == reachable {
                        Ok(address)
                    } else {
                        Err(io::Error::from(io::ErrorKind::ConnectionRefused))
                    }
                },
            )
            .await
            .unwrap();
            assert_eq!(result, reachable);
        }
    }

    #[tokio::test]
    async fn deadline_and_refused_connections_report_different_errors() {
        let timed_out = race_addresses(
            addresses(),
            Duration::ZERO,
            Duration::from_millis(20),
            |_| async { std::future::pending::<io::Result<()>>().await },
        )
        .await
        .unwrap_err();
        assert_eq!(timed_out.kind(), io::ErrorKind::TimedOut);
        assert!(timed_out.to_string().contains("10.0.0.2:3389"));
        let refused = race_addresses(
            addresses(),
            Duration::ZERO,
            Duration::from_secs(1),
            |_| async { Err::<(), _>(io::Error::from(io::ErrorKind::ConnectionRefused)) },
        )
        .await
        .unwrap_err();
        assert_eq!(refused.kind(), io::ErrorKind::ConnectionRefused);
    }

    #[tokio::test]
    async fn pending_attempts_are_dropped_after_success_or_timeout() {
        use std::sync::{
            atomic::{AtomicUsize, Ordering},
            Arc,
        };
        struct Attempt(Arc<AtomicUsize>);
        impl Drop for Attempt {
            fn drop(&mut self) {
                self.0.fetch_sub(1, Ordering::SeqCst);
            }
        }
        for succeeds in [true, false] {
            let alive = Arc::new(AtomicUsize::new(0));
            let reachable = addresses()[2];
            let result = race_addresses(
                addresses(),
                Duration::from_millis(1),
                Duration::from_millis(30),
                |address| {
                    alive.fetch_add(1, Ordering::SeqCst);
                    let attempt = Attempt(Arc::clone(&alive));
                    async move {
                        let _attempt = attempt;
                        if succeeds && address == reachable {
                            return Ok(address);
                        }
                        std::future::pending::<io::Result<SocketAddr>>().await
                    }
                },
            )
            .await;
            assert_eq!(result.is_ok(), succeeds);
            tokio::time::timeout(Duration::from_secs(1), async {
                while alive.load(Ordering::SeqCst) != 0 {
                    tokio::task::yield_now().await;
                }
            })
            .await
            .expect("losing TCP attempts must not outlive cancellation");
        }
    }

    #[tokio::test]
    async fn literal_ip_and_local_tcp_work_without_dns() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let resolved = resolve("127.0.0.1", address.port()).await.unwrap();
        assert_eq!(resolved, vec![address]);
        let stream = connect(resolved).await.unwrap();
        assert_eq!(stream.peer_addr().unwrap(), address);
        assert!(resolve("2001:db8::1", 3390).await.unwrap()[0].is_ipv6());
        let local = resolve("localhost", address.port()).await.unwrap();
        assert!(local.iter().any(|address| address.ip().is_loopback()));
    }
}
