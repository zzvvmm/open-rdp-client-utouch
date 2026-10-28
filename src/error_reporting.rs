//! Opt-out error reporting. Never forward raw errors, panic payloads or Qt messages.
use std::borrow::Cow;
use std::collections::HashMap;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex, OnceLock, Weak,
};
use std::time::{Duration, Instant};

use sentry::protocol::{Event, Exception, Frame, Stacktrace};
use sentry::{Client, ClientOptions};

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum ErrorCode {
    RustPanic,
    RdpDecode,
    RdpSession,
    RdpNegotiation,
    RdpTls,
    QmlReference,
    QmlType,
    QmlBinding,
    QmlLoad,
    QtCritical,
}

impl ErrorCode {
    fn details(self) -> (&'static str, &'static str) {
        match self {
            Self::RustPanic => ("RustPanic", "Unexpected Rust panic"),
            Self::RdpDecode => ("RdpDecodeError", "Remote desktop data could not be decoded"),
            Self::RdpSession => (
                "RdpSessionError",
                "Remote desktop session ended unexpectedly",
            ),
            Self::RdpNegotiation => (
                "RdpNegotiationError",
                "Remote desktop protocol negotiation failed",
            ),
            Self::RdpTls => ("RdpTlsError", "Remote desktop TLS handshake failed"),
            Self::QmlReference => ("QmlReferenceError", "A QML reference could not be resolved"),
            Self::QmlType => ("QmlTypeError", "A QML expression had an unexpected type"),
            Self::QmlBinding => ("QmlBindingError", "A QML binding loop was detected"),
            Self::QmlLoad => ("QmlLoadError", "The QML interface could not be loaded"),
            Self::QtCritical => (
                "QtCriticalError",
                "The Qt interface reported a critical error",
            ),
        }
    }

    fn is_ui(self) -> bool {
        matches!(
            self,
            Self::QmlReference
                | Self::QmlType
                | Self::QmlBinding
                | Self::QmlLoad
                | Self::QtCritical
        )
    }

    pub fn from_ui(code: &str) -> Option<Self> {
        match code {
            "qml_reference" => Some(Self::QmlReference),
            "qml_type" => Some(Self::QmlType),
            "qml_binding" => Some(Self::QmlBinding),
            "qml_load" => Some(Self::QmlLoad),
            "qt_critical" => Some(Self::QtCritical),
            _ => None,
        }
    }
}

pub fn backend_error(reason: &str) -> Option<ErrorCode> {
    // Offline PCs, DNS failures, timeouts, rejected certificates and bad input
    // are expected control flow. None of their free-form text leaves the app.
    if reason.starts_with("RDP session terminated:") {
        Some(
            if reason.contains("decode") || reason.contains("decompress") {
                ErrorCode::RdpDecode
            } else {
                ErrorCode::RdpSession
            },
        )
    } else if reason.starts_with("RDP negotiation failed:") {
        Some(ErrorCode::RdpNegotiation)
    } else if reason.starts_with("TLS handshake failed:") {
        Some(ErrorCode::RdpTls)
    } else {
        None
    }
}

static CURRENT: OnceLock<Mutex<Weak<ErrorReporter>>> = OnceLock::new();
#[cfg(not(test))]
static PANIC_HOOK: std::sync::Once = std::sync::Once::new();

pub struct ErrorReporter {
    enabled: Arc<AtomicBool>,
    backend: Option<Client>,
    ui: Option<Client>,
    recent: Mutex<HashMap<(ErrorCode, String, u32), Instant>>,
}

impl ErrorReporter {
    pub fn new(enabled: bool) -> Arc<Self> {
        // Use the same Rustls provider as IronRDP; no OpenSSL dependency on phones.
        let _ = tokio_rustls::rustls::crypto::ring::default_provider().install_default();
        let enabled = Arc::new(AtomicBool::new(enabled));
        let config: serde_json::Value =
            serde_json::from_str(include_str!("../sentry.json")).unwrap_or_default();
        let reporter = Arc::new(Self {
            backend: Self::client(
                config["backend_dsn"].as_str().unwrap_or_default(),
                Arc::clone(&enabled),
            ),
            ui: Self::client(
                config["ui_dsn"].as_str().unwrap_or_default(),
                Arc::clone(&enabled),
            ),
            enabled,
            recent: Mutex::new(HashMap::new()),
        });
        if let Ok(mut current) = CURRENT.get_or_init(Default::default).lock() {
            *current = Arc::downgrade(&reporter);
        }
        #[cfg(not(test))]
        PANIC_HOOK.call_once(|| {
            let previous = std::panic::take_hook();
            std::panic::set_hook(Box::new(move |info| {
                if let Some(reporter) = current() {
                    if let Some(location) = info.location() {
                        reporter.capture(ErrorCode::RustPanic, location.file(), location.line());
                    } else {
                        reporter.capture(ErrorCode::RustPanic, "", 0);
                    }
                    // extern-C unwinding can abort: give the dedicated SDK worker
                    // a bounded chance to deliver before the process terminates.
                    reporter.flush(Duration::from_secs(2));
                }
                previous(info);
            }));
        });
        reporter
    }

    fn client(dsn: &str, enabled: Arc<AtomicBool>) -> Option<Client> {
        let dsn = dsn.parse::<sentry::types::Dsn>().ok()?;
        let mut options = ClientOptions::new()
            .default_integrations(false)
            .send_default_pii(false)
            .traces_sample_rate(0.0)
            .max_breadcrumbs(0)
            .transport_channel_capacity(16)
            .before_send(move |event| {
                if enabled.load(Ordering::SeqCst) {
                    sanitize(event)
                } else {
                    None
                }
            });
        options.dsn = Some(dsn);
        let mut options = sentry::apply_defaults(options);
        options.accept_invalid_certs = false;
        #[cfg(test)]
        {
            options.transport = Some(Arc::new(|_: &ClientOptions| {
                Arc::new(DiscardTransport) as Arc<dyn sentry::Transport>
            }));
        }
        // A failed optional reporter must not stop users connecting to their PC.
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            Client::from_config(options)
        }))
        .ok()
    }

    pub fn set_enabled(&self, enabled: bool) {
        self.enabled.store(enabled, Ordering::SeqCst);
    }

    pub fn is_configured(&self) -> bool {
        self.backend.is_some() && self.ui.is_some()
    }

    pub fn capture(&self, code: ErrorCode, file: &str, line: u32) -> sentry::types::Uuid {
        if !self.enabled.load(Ordering::SeqCst) {
            return sentry::types::Uuid::nil();
        }
        let key = (code, source_file(file).unwrap_or_default(), line);
        if let Ok(mut recent) = self.recent.try_lock() {
            if recent
                .get(&key)
                .is_some_and(|time| time.elapsed() < Duration::from_secs(60))
            {
                return sentry::types::Uuid::nil();
            }
            if recent.len() >= 128 && !recent.contains_key(&key) {
                return sentry::types::Uuid::nil();
            }
            recent.insert(key, Instant::now());
        } else {
            return sentry::types::Uuid::nil();
        }
        let (ty, value) = code.details();
        let mut frames = sentry::integrations::backtrace::current_stacktrace()
            .map(|trace| trace.frames)
            .unwrap_or_default();
        if let Some(file) = source_file(file) {
            let function = frames
                .iter()
                .rev()
                .find(|frame| {
                    frame
                        .abs_path
                        .as_deref()
                        .and_then(source_file)
                        .or_else(|| frame.filename.as_deref().and_then(source_file))
                        .as_deref()
                        == Some(file.as_str())
                        && frame.lineno == Some(line.into())
                })
                .and_then(|frame| frame.function.clone());
            frames.push(Frame {
                filename: Some(file),
                function,
                lineno: Some(line.into()),
                in_app: Some(true),
                ..Default::default()
            });
        }
        let event = Event {
            exception: vec![Exception {
                ty: ty.to_string(),
                value: Some(value.to_string()),
                stacktrace: Some(Stacktrace {
                    frames,
                    ..Default::default()
                }),
                ..Default::default()
            }]
            .into(),
            tags: [("error.code".to_string(), ty.to_string())].into(),
            ..Default::default()
        };
        let client = if code.is_ui() {
            &self.ui
        } else {
            &self.backend
        };
        client
            .as_ref()
            .map(|client| client.capture_event(event, None))
            .unwrap_or_default()
    }

    pub fn flush(&self, timeout: Duration) -> bool {
        let backend = self
            .backend
            .as_ref()
            .is_none_or(|client| client.flush(Some(timeout / 2)));
        let ui = self
            .ui
            .as_ref()
            .is_none_or(|client| client.flush(Some(timeout / 2)));
        backend && ui
    }
}

impl Drop for ErrorReporter {
    fn drop(&mut self) {
        self.flush(Duration::from_millis(500));
    }
}

pub fn current() -> Option<Arc<ErrorReporter>> {
    CURRENT.get()?.try_lock().ok()?.upgrade()
}

fn source_file(file: &str) -> Option<String> {
    let file = file
        .strip_prefix(concat!(env!("CARGO_MANIFEST_DIR"), "/"))
        .unwrap_or(file);
    let file = file.strip_prefix("qrc:/").unwrap_or(file);
    if !file.split('/').any(|part| part == "..")
        && !file.contains(['?', '#', '\\'])
        && (file.starts_with("src/") || file.starts_with("qml/") || file.starts_with("qt/"))
        && file.len() < 200
        && (!file.starts_with("qml/")
            || include_str!("../resources.qrc").contains(&format!("<file>{file}</file>")))
    {
        Some(file.to_string())
    } else {
        None
    }
}

fn sanitize(event: Event<'static>) -> Option<Event<'static>> {
    let code = [
        ErrorCode::RustPanic,
        ErrorCode::RdpDecode,
        ErrorCode::RdpSession,
        ErrorCode::RdpNegotiation,
        ErrorCode::RdpTls,
        ErrorCode::QmlReference,
        ErrorCode::QmlType,
        ErrorCode::QmlBinding,
        ErrorCode::QmlLoad,
        ErrorCode::QtCritical,
    ]
    .into_iter()
    .find(|code| event.tags.get("error.code").map(String::as_str) == Some(code.details().0))?;
    let (ty, value) = code.details();
    let frames: Vec<Frame> = event
        .exception
        .iter()
        .flat_map(|ex| ex.stacktrace.iter())
        .flat_map(|trace| trace.frames.iter())
        .filter_map(|frame| {
            let file = frame
                .abs_path
                .as_deref()
                .and_then(source_file)
                .or_else(|| frame.filename.as_deref().and_then(source_file))?;
            Some(Frame {
                filename: Some(file),
                function: frame.function.clone(),
                lineno: frame.lineno,
                colno: frame.colno,
                in_app: Some(true),
                ..Default::default()
            })
        })
        .collect();
    let mut fingerprint = vec![Cow::Borrowed("rdp-client-ut"), Cow::Borrowed(ty)];
    if let Some(frame) = frames.last() {
        fingerprint.push(Cow::Owned(frame.filename.clone().unwrap_or_default()));
        fingerprint.push(Cow::Owned(frame.lineno.unwrap_or_default().to_string()));
    }
    Some(Event {
        event_id: event.event_id,
        timestamp: event.timestamp,
        sdk: event.sdk,
        platform: Cow::Borrowed("native"),
        release: Some(Cow::Borrowed(concat!(
            env!("CARGO_PKG_NAME"),
            "@",
            env!("CARGO_PKG_VERSION")
        ))),
        environment: Some(Cow::Borrowed(if cfg!(debug_assertions) {
            "development"
        } else {
            "production"
        })),
        exception: vec![Exception {
            ty: ty.to_string(),
            value: Some(value.to_string()),
            stacktrace: Some(Stacktrace {
                frames,
                ..Default::default()
            }),
            ..Default::default()
        }]
        .into(),
        fingerprint: Cow::Owned(fingerprint),
        tags: [
            ("error.code".into(), ty.into()),
            (
                "component".into(),
                if code.is_ui() { "qt-qml" } else { "rust" }.into(),
            ),
            ("architecture".into(), std::env::consts::ARCH.into()),
            (
                "framework".into(),
                crate::storage::database::APP_FRAMEWORK.into(),
            ),
        ]
        .into(),
        ..Default::default()
    })
}

#[cfg(test)]
struct DiscardTransport;
#[cfg(test)]
impl sentry::Transport for DiscardTransport {
    fn send_envelope(&self, _: sentry::Envelope) {}
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Recorder(Arc<Mutex<Vec<Event<'static>>>>);
    impl sentry::Transport for Recorder {
        fn send_envelope(&self, envelope: sentry::Envelope) {
            if let Some(event) = envelope.event() {
                self.0.lock().unwrap().push(event.clone());
            }
        }
    }

    fn recording() -> (ErrorReporter, Arc<Mutex<Vec<Event<'static>>>>) {
        let mut reporter = Arc::try_unwrap(ErrorReporter::new(true)).ok().unwrap();
        let events = Arc::new(Mutex::new(Vec::new()));
        for client in [&mut reporter.backend, &mut reporter.ui] {
            let mut options = client.as_ref().unwrap().options().clone();
            let recorded = Arc::clone(&events);
            options.transport = Some(Arc::new(move |_: &ClientOptions| {
                Arc::new(Recorder(Arc::clone(&recorded))) as Arc<dyn sentry::Transport>
            }));
            *client = Some(Client::from_config(options));
        }
        (reporter, events)
    }

    #[test]
    fn opt_out_and_reenable_gate_both_projects_immediately() {
        let (reporter, events) = recording();
        assert!(!reporter
            .capture(ErrorCode::RdpDecode, "src/lib.rs", 1)
            .is_nil());
        reporter.set_enabled(false);
        assert!(reporter
            .capture(ErrorCode::QmlType, "qrc:/qml/Main.qml", 2)
            .is_nil());
        assert_eq!(events.lock().unwrap().len(), 1);
        reporter.set_enabled(true);
        assert!(!reporter
            .capture(ErrorCode::QmlType, "qrc:/qml/Main.qml", 2)
            .is_nil());
        let events = events.lock().unwrap();
        assert_eq!(events.len(), 2);
        assert_eq!(events[0].tags["component"], "rust");
        assert_eq!(events[1].tags["component"], "qt-qml");
        assert_eq!(events[1].platform, "native");
    }

    #[test]
    fn repeated_errors_are_throttled_but_distinct_code_locations_survive() {
        let (reporter, events) = recording();
        reporter.capture(ErrorCode::RustPanic, "src/lib.rs", 10);
        assert!(reporter
            .capture(ErrorCode::RustPanic, "src/lib.rs", 10)
            .is_nil());
        reporter.capture(ErrorCode::RustPanic, "src/lib.rs", 20);
        let events = events.lock().unwrap();
        assert_eq!(events.len(), 2);
        assert_ne!(events[0].fingerprint, events[1].fingerprint);
    }

    #[test]
    fn sanitization_rebuilds_an_allowlisted_event_without_private_data() {
        let mut event = Event::default();
        event.message = Some("private-password@192.168.1.42".into());
        event.tags.insert("error.code".into(), "RustPanic".into());
        event.tags.insert("hostname".into(), "private-host".into());
        event
            .extra
            .insert("clipboard".into(), serde_json::json!("private-clipboard"));
        event.user = Some(sentry::protocol::User {
            email: Some("private-user@example.test".into()),
            ..Default::default()
        });
        event.exception = vec![Exception {
            ty: "private-panic-payload".into(),
            value: Some("private-credentials".into()),
            stacktrace: Some(Stacktrace {
                frames: vec![Frame {
                    filename: Some("src/lib.rs".into()),
                    lineno: Some(123),
                    abs_path: Some("/home/private-user/src/lib.rs".into()),
                    context_line: Some("private-source-context".into()),
                    vars: [("password".into(), serde_json::json!("private-variable"))].into(),
                    ..Default::default()
                }],
                ..Default::default()
            }),
            ..Default::default()
        }]
        .into();
        let event = sanitize(event).unwrap();
        let serialized = serde_json::to_string(&event).unwrap();
        assert!(!serialized.contains("private-"), "{serialized}");
        assert!(!serialized.contains("192.168.1.42"));
        assert_eq!(
            event.exception[0].stacktrace.as_ref().unwrap().frames[0].lineno,
            Some(123)
        );
        assert_eq!(
            event.release.unwrap(),
            concat!(env!("CARGO_PKG_NAME"), "@", env!("CARGO_PKG_VERSION"))
        );
        assert!(sanitize(Event::default()).is_none());
        assert!(source_file("qrc:/qml/not-shipped.qml").is_none());
    }

    #[test]
    fn expected_connection_failures_stay_local() {
        for message in [
            "Could not resolve 'private-host'",
            "TCP connection failed: timed out",
            "Connection cancelled: certificate not trusted",
            "Invalid RDP port",
            "Authentication / session activation failed: STATUS_LOGON_FAILURE",
        ] {
            assert_eq!(backend_error(message), None);
        }
        assert_eq!(
            backend_error("RDP session terminated: [decode error] private-host"),
            Some(ErrorCode::RdpDecode)
        );
        assert_eq!(
            backend_error("TLS handshake failed: private-host"),
            Some(ErrorCode::RdpTls)
        );
    }
}
