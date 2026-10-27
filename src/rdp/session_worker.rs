use core::net::{IpAddr, Ipv4Addr, Ipv6Addr};
use core::time::Duration;
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use std::thread;

use ironrdp_cliprdr::backend::ClipboardMessage;
use ironrdp_connector::connection_activation::ConnectionActivationState;
use ironrdp_connector::sspi::{self, Error as SspiError, ErrorKind as SspiErrorKind};
use ironrdp_connector::{
    custom_err, general_err, BitmapConfig, ClientConnector, ConnectionResult, ConnectorResult,
    Credentials, DesktopSize, ServerName as RdpServerName,
};
use ironrdp_core::WriteBuf;
use ironrdp_displaycontrol::client::DisplayControlClient;
use ironrdp_displaycontrol::pdu::MonitorLayoutEntry;
use ironrdp_dvc::DrdynvcClient;
use ironrdp_echo::client::EchoClient;
use ironrdp_graphics::image_processing::PixelFormat;
use ironrdp_pdu::gcc::KeyboardType;
use ironrdp_pdu::geometry::Rectangle as _;
use ironrdp_pdu::input::fast_path::FastPathInputEvent;
use ironrdp_pdu::input::mouse::PointerFlags;
use ironrdp_pdu::rdp::capability_sets::{client_codecs_capabilities, MajorPlatformType};
use ironrdp_pdu::rdp::client_info::{CompressionType, PerformanceFlags, TimezoneInfo};
use ironrdp_session::image::DecodedImage;
use ironrdp_session::{
    fast_path, ActiveStageBuilder, ActiveStageOutput, GracefulDisconnectReason, SessionResult,
};
use ironrdp_tokio::{
    single_sequence_step_read, split_tokio_framed, FramedWrite as _, NetworkClient,
    TokioFramed,
};
use serde::{Deserialize, Serialize};
use smallvec::SmallVec;
use tokio::io::{AsyncRead, AsyncReadExt as _, AsyncWrite, AsyncWriteExt as _};
use tokio::net::{TcpStream, UdpSocket};
use tokio::sync::{mpsc, oneshot};
use url::Url;

use crate::models::cert_store::{
    inspect_x509_certificate, CertStore, CertTrustDecision, CertVerificationOutcome,
    CertificateInfo,
};
use crate::models::AudioRedirectionMode;
use crate::rdp::audio::{PcmAudioChunk, UtRdpsndHandler};
use crate::rdp::canvas_item::{DirtyRect, SharedFrameBuffer};
use crate::rdp::clipboard::UtClipboardBackend;
use crate::rdp::transport;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SessionStage {
    Disconnected,
    Resolving,
    ConnectingTcp,
    TlsHandshake,
    VerifyingCertificate,
    AuthenticatingNla,
    ActivatingSession,
    Connected,
    Reconnecting,
    Error,
}

impl SessionStage {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Disconnected => "disconnected",
            Self::Resolving => "resolving",
            Self::ConnectingTcp => "connecting_tcp",
            Self::TlsHandshake => "tls_handshake",
            Self::VerifyingCertificate => "verifying_certificate",
            Self::AuthenticatingNla => "authenticating_nla",
            Self::ActivatingSession => "activating_session",
            Self::Connected => "connected",
            Self::Reconnecting => "reconnecting",
            Self::Error => "error",
        }
    }

    pub fn human_label(&self) -> &'static str {
        match self {
            Self::Disconnected => "Disconnected",
            Self::Resolving => "Resolving PC address…",
            Self::ConnectingTcp => "Connecting to remote PC (TCP 3389)…",
            Self::TlsHandshake => "Performing TLS security handshake…",
            Self::VerifyingCertificate => "Verifying server TLS certificate…",
            Self::AuthenticatingNla => "Authenticating with CredSSP / NLA…",
            Self::ActivatingSession => "Preparing remote desktop display…",
            Self::Connected => "Connected",
            Self::Reconnecting => "Adjusting remote display resolution…",
            Self::Error => "Connection failed",
        }
    }
}

#[derive(Debug, Clone)]
pub struct RdpSessionConfig {
    pub profile_id: String,
    pub friendly_name: String,
    pub hostname: String,
    pub port: u16,
    pub username: String,
    pub password: String,
    pub domain: String,
    pub width: u16,
    pub height: u16,
    pub scale_factor: u32,
    pub enable_tls: bool,
    pub enable_nla: bool,
    pub clipboard_redirection: bool,
    pub audio_mode: AudioRedirectionMode,
    pub temp_dir: String,
}

#[derive(Debug)]
pub enum RdpCommand {
    FastPathInput(SmallVec<[FastPathInputEvent; 4]>),
    ResizeDesktop {
        width: u16,
        height: u16,
        scale_factor: u32,
    },
    SetLocalClipboardText(String),
    Disconnect,
}

#[derive(Debug, Clone)]
pub enum RdpWorkerEvent {
    StageChanged {
        profile_id: String,
        stage: SessionStage,
        detail: String,
    },
    CertificatePrompt {
        profile_id: String,
        cert: CertificateInfo,
    },
    DesktopResized {
        width: u16,
        height: u16,
    },
    FrameUpdated {
        dirty: DirtyRect,
        fps: u32,
    },
    RemoteClipboardChanged {
        text: String,
    },
    AudioChunk(PcmAudioChunk),
    SessionEnded {
        profile_id: String,
        reason: String,
        is_error: bool,
    },
}

pub struct RdpSessionHandle {
    pub profile_id: String,
    pub cmd_tx: mpsc::UnboundedSender<RdpCommand>,
    cert_decision_tx: Mutex<Option<oneshot::Sender<CertTrustDecision>>>,
}

impl RdpSessionHandle {
    pub fn send_command(&self, cmd: RdpCommand) -> bool {
        self.cmd_tx.send(cmd).is_ok()
    }

    pub fn respond_certificate(&self, decision: CertTrustDecision) -> bool {
        if let Ok(mut guard) = self.cert_decision_tx.lock() {
            if let Some(tx) = guard.take() {
                return tx.send(decision).is_ok();
            }
        }
        false
    }
}

pub fn spawn_rdp_session(
    config: RdpSessionConfig,
    framebuffer: Arc<Mutex<SharedFrameBuffer>>,
    cert_store: Arc<Mutex<CertStore>>,
    event_callback: Arc<dyn Fn(RdpWorkerEvent) + Send + Sync + 'static>,
) -> Arc<RdpSessionHandle> {
    let (cmd_tx, cmd_rx) = mpsc::unbounded_channel();
    let (cert_tx, cert_rx) = oneshot::channel();
    let profile_id = config.profile_id.clone();

    let handle = Arc::new(RdpSessionHandle {
        profile_id: profile_id.clone(),
        cmd_tx,
        cert_decision_tx: Mutex::new(Some(cert_tx)),
    });

    thread::Builder::new()
        .name(format!("rdp-worker-{profile_id}"))
        .spawn(move || {
            let rt = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .expect("Tokio runtime for RDP worker");
            rt.block_on(async move {
                run_session_lifecycle(
                    config,
                    framebuffer,
                    cert_store,
                    cmd_rx,
                    cert_rx,
                    event_callback,
                )
                .await;
            });
        })
        .expect("Failed to spawn RDP worker thread");

    handle
}

async fn run_session_lifecycle(
    mut config: RdpSessionConfig,
    framebuffer: Arc<Mutex<SharedFrameBuffer>>,
    cert_store: Arc<Mutex<CertStore>>,
    mut cmd_rx: mpsc::UnboundedReceiver<RdpCommand>,
    cert_rx: oneshot::Receiver<CertTrustDecision>,
    emit: Arc<dyn Fn(RdpWorkerEvent) + Send + Sync + 'static>,
) {
    let profile_id = config.profile_id.clone();

    // Built-in interactive Demo PC support ("demo", "demo.local", "demo-pc")
    if is_demo_hostname(&config.hostname) {
        run_demo_session(
            config,
            framebuffer,
            cert_store,
            &mut cmd_rx,
            cert_rx,
            emit,
        )
        .await;
        return;
    }

    let mut cert_rx_opt = Some(cert_rx);
    let local_clipboard_text = Arc::new(Mutex::new(String::new()));
    let mut pending_commands = VecDeque::new();

    loop {
        let (clipboard_msg_tx, mut clipboard_msg_rx) = mpsc::unbounded_channel();
        let connecting = connect_and_authenticate(
            &config,
            &cert_store,
            &mut cert_rx_opt,
            &local_clipboard_text,
            &clipboard_msg_tx,
            &emit,
        );
        // Cancel DNS, TCP, and stalled negotiations promptly when leaving the
        // session view; an old worker must not connect after the user gives up.
        let connect_res = tokio::select! {
            result = connecting => result,
            _ = async {
                while let Some(command) = cmd_rx.recv().await {
                    if matches!(command, RdpCommand::Disconnect) { break; }
                    // Preserve input/resize commands received during the handshake.
                    pending_commands.push_back(command);
                }
            } => {
                emit(RdpWorkerEvent::SessionEnded {
                    profile_id,
                    reason: "Connection cancelled".to_string(),
                    is_error: false,
                });
                return;
            }
        };

        let (connection_result, framed) = match connect_res {
            Ok(pair) => pair,
            Err(err_msg) => {
                emit(RdpWorkerEvent::StageChanged {
                    profile_id: profile_id.clone(),
                    stage: SessionStage::Error,
                    detail: err_msg.clone(),
                });
                emit(RdpWorkerEvent::SessionEnded {
                    profile_id,
                    reason: err_msg,
                    is_error: true,
                });
                return;
            }
        };

        let w = connection_result.desktop_size.width;
        let h = connection_result.desktop_size.height;
        if let Ok(mut fb) = framebuffer.lock() {
            fb.resize_clear(w, h);
        }
        emit(RdpWorkerEvent::DesktopResized {
            width: w,
            height: h,
        });
        emit(RdpWorkerEvent::StageChanged {
            profile_id: profile_id.clone(),
            stage: SessionStage::Connected,
            detail: format!("Connected ({w}×{h})"),
        });

        match drive_active_session(
            framed,
            connection_result,
            &framebuffer,
            &local_clipboard_text,
            &clipboard_msg_tx,
            &mut clipboard_msg_rx,
            &mut cmd_rx,
            &mut pending_commands,
            &emit,
        )
        .await
        {
            Ok(SessionLoopFlow::ReconnectWithNewSize { width, height }) => {
                config.width = width;
                config.height = height;
                emit(RdpWorkerEvent::StageChanged {
                    profile_id: profile_id.clone(),
                    stage: SessionStage::Reconnecting,
                    detail: format!("Resizing desktop to {width}×{height}…"),
                });
                continue;
            }
            Ok(SessionLoopFlow::TerminatedGracefully(reason)) => {
                emit(RdpWorkerEvent::StageChanged {
                    profile_id: profile_id.clone(),
                    stage: SessionStage::Disconnected,
                    detail: reason.to_string(),
                });
                emit(RdpWorkerEvent::SessionEnded {
                    profile_id,
                    reason: reason.to_string(),
                    is_error: false,
                });
                break;
            }
            Err(e) => {
                let msg = format!("RDP session terminated: {e}");
                emit(RdpWorkerEvent::StageChanged {
                    profile_id: profile_id.clone(),
                    stage: SessionStage::Error,
                    detail: msg.clone(),
                });
                emit(RdpWorkerEvent::SessionEnded {
                    profile_id,
                    reason: msg,
                    is_error: true,
                });
                break;
            }
        }
    }
}

fn is_demo_hostname(host: &str) -> bool {
    let lower = host.trim().to_ascii_lowercase();
    lower == "demo" || lower == "demo.local" || lower == "demo-pc" || lower.starts_with("demo.")
}

async fn run_demo_session(
    mut config: RdpSessionConfig,
    framebuffer: Arc<Mutex<SharedFrameBuffer>>,
    cert_store: Arc<Mutex<CertStore>>,
    cmd_rx: &mut mpsc::UnboundedReceiver<RdpCommand>,
    cert_rx: oneshot::Receiver<CertTrustDecision>,
    emit: Arc<dyn Fn(RdpWorkerEvent) + Send + Sync + 'static>,
) {
    let profile_id = config.profile_id.clone();
    emit(RdpWorkerEvent::StageChanged {
        profile_id: profile_id.clone(),
        stage: SessionStage::Resolving,
        detail: SessionStage::Resolving.human_label().to_string(),
    });
    tokio::time::sleep(Duration::from_millis(120)).await;

    emit(RdpWorkerEvent::StageChanged {
        profile_id: profile_id.clone(),
        stage: SessionStage::TlsHandshake,
        detail: SessionStage::TlsHandshake.human_label().to_string(),
    });
    tokio::time::sleep(Duration::from_millis(120)).await;

    let demo_cert = CertificateInfo {
        host: config.hostname.clone(),
        port: config.port,
        subject_cn: format!("CN={}", config.hostname),
        issuer_cn: "CN=Windows Self-Signed RDP Authority".to_string(),
        valid_from: "2026-01-01 00:00:00 UTC".to_string(),
        valid_until: "2027-01-01 00:00:00 UTC".to_string(),
        sha256_fingerprint:
            "E4:8A:91:3C:7B:10:42:9F:C1:88:20:5D:3B:7A:09:11:6E:55:4F:12:89:A0:B3:C4:D5:E6:F7:01:23:45:67:89"
                .to_string(),
        status_reason: "First connection to this PC (Trust-On-First-Use)".to_string(),
        is_mismatch_warning: false,
    };

    let outcome = cert_store
        .lock()
        .map(|s| s.verify(&demo_cert))
        .unwrap_or(CertVerificationOutcome::Trusted);

    if let CertVerificationOutcome::UnknownHost(prompt_cert)
    | CertVerificationOutcome::FingerprintMismatch {
        actual: prompt_cert,
        ..
    } = outcome
    {
        emit(RdpWorkerEvent::StageChanged {
            profile_id: profile_id.clone(),
            stage: SessionStage::VerifyingCertificate,
            detail: SessionStage::VerifyingCertificate.human_label().to_string(),
        });
        emit(RdpWorkerEvent::CertificatePrompt {
            profile_id: profile_id.clone(),
            cert: prompt_cert.clone(),
        });

        match cert_rx.await {
            Ok(decision) if decision != CertTrustDecision::Reject => {
                if let Ok(mut store) = cert_store.lock() {
                    store.record_decision(&prompt_cert, decision);
                }
            }
            _ => {
                emit(RdpWorkerEvent::SessionEnded {
                    profile_id,
                    reason: "Certificate trust rejected by user".to_string(),
                    is_error: false,
                });
                return;
            }
        }
    }

    emit(RdpWorkerEvent::StageChanged {
        profile_id: profile_id.clone(),
        stage: SessionStage::AuthenticatingNla,
        detail: SessionStage::AuthenticatingNla.human_label().to_string(),
    });
    tokio::time::sleep(Duration::from_millis(150)).await;

    let mut win_pos = (config.width / 5, config.height / 6);
    let mut dragging_window = false;
    let mut drag_offset = (0i32, 0i32);
    let mut last_cursor = (config.width / 2, config.height / 2);

    if let Ok(mut fb) = framebuffer.lock() {
        fb.render_demo_desktop(config.width, config.height, win_pos, None);
    }
    emit(RdpWorkerEvent::DesktopResized {
        width: config.width,
        height: config.height,
    });
    emit(RdpWorkerEvent::StageChanged {
        profile_id: profile_id.clone(),
        stage: SessionStage::Connected,
        detail: format!("Connected to Demo Desktop ({}×{})", config.width, config.height),
    });
    emit(RdpWorkerEvent::FrameUpdated {
        dirty: DirtyRect {
            x: 0,
            y: 0,
            width: config.width,
            height: config.height,
        },
        fps: 60,
    });

    while let Some(cmd) = cmd_rx.recv().await {
        match cmd {
            RdpCommand::Disconnect => {
                emit(RdpWorkerEvent::StageChanged {
                    profile_id: profile_id.clone(),
                    stage: SessionStage::Disconnected,
                    detail: "Disconnected".to_string(),
                });
                emit(RdpWorkerEvent::SessionEnded {
                    profile_id,
                    reason: "User disconnected".to_string(),
                    is_error: false,
                });
                break;
            }
            RdpCommand::ResizeDesktop { width, height, .. } => {
                config.width = width.max(320);
                config.height = height.max(240);
                if let Ok(mut fb) = framebuffer.lock() {
                    fb.render_demo_desktop(config.width, config.height, win_pos, None);
                }
                emit(RdpWorkerEvent::DesktopResized {
                    width: config.width,
                    height: config.height,
                });
                emit(RdpWorkerEvent::FrameUpdated {
                    dirty: DirtyRect {
                        x: 0,
                        y: 0,
                        width: config.width,
                        height: config.height,
                    },
                    fps: 60,
                });
            }
            RdpCommand::SetLocalClipboardText(text) => {
                emit(RdpWorkerEvent::RemoteClipboardChanged { text });
            }
            RdpCommand::FastPathInput(events) => {
                let mut click_ripple = None;
                for ev in events {
                    if let FastPathInputEvent::MouseEvent(m) = ev {
                        last_cursor = (m.x_position, m.y_position);
                        if m.flags.contains(PointerFlags::LEFT_BUTTON | PointerFlags::DOWN) {
                            click_ripple = Some(last_cursor);
                            if m.x_position >= win_pos.0
                                && m.x_position <= win_pos.0 + (config.width * 3 / 5)
                                && m.y_position >= win_pos.1
                                && m.y_position <= win_pos.1 + 40
                            {
                                dragging_window = true;
                                drag_offset = (
                                    i32::from(m.x_position) - i32::from(win_pos.0),
                                    i32::from(m.y_position) - i32::from(win_pos.1),
                                );
                            }
                        } else if m.flags.contains(PointerFlags::LEFT_BUTTON)
                            && !m.flags.contains(PointerFlags::DOWN)
                        {
                            dragging_window = false;
                        } else if m.flags.contains(PointerFlags::MOVE) && dragging_window {
                            let nx = (i32::from(m.x_position) - drag_offset.0).max(8) as u16;
                            let ny = (i32::from(m.y_position) - drag_offset.1).max(8) as u16;
                            win_pos = (nx, ny);
                        }
                    }
                }
                if let Ok(mut fb) = framebuffer.lock() {
                    fb.set_cursor_position(last_cursor.0, last_cursor.1);
                    if dragging_window || click_ripple.is_some() {
                        fb.render_demo_desktop(config.width, config.height, win_pos, click_ripple);
                    }
                }
                emit(RdpWorkerEvent::FrameUpdated {
                    dirty: DirtyRect {
                        x: 0,
                        y: 0,
                        width: config.width,
                        height: config.height,
                    },
                    fps: 60,
                });
            }
        }
    }
}

trait AsyncReadWrite: AsyncRead + AsyncWrite {}
impl<T> AsyncReadWrite for T where T: AsyncRead + AsyncWrite {}
type UpgradedFramed = TokioFramed<Box<dyn AsyncReadWrite + Unpin + Send + Sync>>;

async fn connect_and_authenticate(
    config: &RdpSessionConfig,
    cert_store: &Arc<Mutex<CertStore>>,
    cert_rx_opt: &mut Option<oneshot::Receiver<CertTrustDecision>>,
    local_clipboard_text: &Arc<Mutex<String>>,
    clipboard_msg_tx: &mpsc::UnboundedSender<ClipboardMessage>,
    emit: &Arc<dyn Fn(RdpWorkerEvent) + Send + Sync + 'static>,
) -> Result<(ConnectionResult, UpgradedFramed), String> {
    let profile_id = config.profile_id.clone();

    emit(RdpWorkerEvent::StageChanged {
        profile_id: profile_id.clone(),
        stage: SessionStage::Resolving,
        detail: format!("Resolving {}:{}…", config.hostname, config.port),
    });

    let addresses = transport::resolve(&config.hostname, config.port).await?;
    let dest = addresses
        .iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .join(", ");

    emit(RdpWorkerEvent::StageChanged {
        profile_id: profile_id.clone(),
        stage: SessionStage::ConnectingTcp,
        detail: format!("Connecting to {dest}…"),
    });

    let stream = transport::connect(addresses).await?;

    let _ = stream.set_nodelay(true);
    let client_addr = stream
        .local_addr()
        .map_err(|e| format!("Failed to read local socket address: {e}"))?;

    let mut framed = TokioFramed::new(stream);
    let mut connector = build_client_connector(
        config,
        client_addr,
        local_clipboard_text,
        clipboard_msg_tx,
        emit,
    )?;

    let should_upgrade = tokio::time::timeout(
        Duration::from_secs(20),
        ironrdp_tokio::connect_begin(&mut framed, &mut connector),
    )
        .await
        .map_err(|_| "RDP negotiation timed out after TCP connected. Check the RDP port and server; over VPN, also check tunnel MTU and packet filtering.".to_string())?
        .map_err(|e| format!("RDP negotiation failed: {e}"))?;

    emit(RdpWorkerEvent::StageChanged {
        profile_id: profile_id.clone(),
        stage: SessionStage::TlsHandshake,
        detail: SessionStage::TlsHandshake.human_label().to_string(),
    });

    let (initial_stream, leftover_bytes) = framed.into_inner();
    let (tls_stream, tls_cert) = tokio::time::timeout(
        Duration::from_secs(20),
        ironrdp_tls::upgrade(initial_stream, &config.hostname),
    )
        .await
        .map_err(|_| "TLS handshake timed out after TCP connected. Check the server; over VPN, also check tunnel MTU and packet filtering.".to_string())?
        .map_err(|e| format!("TLS handshake failed: {e}"))?;

    // Inspect server certificate & enforce TOFU before sending NLA credentials
    let cert_info = inspect_x509_certificate(&config.hostname, config.port, &tls_cert)?;
    let verification = cert_store
        .lock()
        .map(|s| s.verify(&cert_info))
        .unwrap_or(CertVerificationOutcome::Trusted);

    match verification {
        CertVerificationOutcome::Trusted => {}
        CertVerificationOutcome::UnknownHost(prompt_cert)
        | CertVerificationOutcome::FingerprintMismatch {
            actual: prompt_cert,
            ..
        } => {
            emit(RdpWorkerEvent::StageChanged {
                profile_id: profile_id.clone(),
                stage: SessionStage::VerifyingCertificate,
                detail: SessionStage::VerifyingCertificate.human_label().to_string(),
            });
            emit(RdpWorkerEvent::CertificatePrompt {
                profile_id: profile_id.clone(),
                cert: prompt_cert.clone(),
            });

            if let Some(rx) = cert_rx_opt.take() {
                match rx.await {
                    Ok(decision) if decision != CertTrustDecision::Reject => {
                        if let Ok(mut store) = cert_store.lock() {
                            store.record_decision(&prompt_cert, decision);
                        }
                    }
                    _ => {
                        return Err("Connection cancelled: certificate not trusted".to_string());
                    }
                }
            } else {
                return Err("Untrusted server certificate".to_string());
            }
        }
    }

    let upgraded = ironrdp_tokio::mark_as_upgraded(should_upgrade, &mut connector);
    let erased_stream: Box<dyn AsyncReadWrite + Unpin + Send + Sync> = Box::new(tls_stream);
    let mut upgraded_framed = TokioFramed::new_with_leftover(erased_stream, leftover_bytes);

    let server_public_key = ironrdp_tls::extract_tls_server_public_key(&tls_cert)
        .ok_or_else(|| "Unable to extract TLS server public key".to_string())?
        .to_owned();

    emit(RdpWorkerEvent::StageChanged {
        profile_id: profile_id.clone(),
        stage: SessionStage::AuthenticatingNla,
        detail: SessionStage::AuthenticatingNla.human_label().to_string(),
    });

    let mut net_client = TokioNetworkClient;
    let server_name = RdpServerName::new(&config.hostname);

    let connection_result = tokio::time::timeout(Duration::from_secs(45), ironrdp_tokio::connect_finalize(
        upgraded,
        connector,
        &mut upgraded_framed,
        &mut net_client,
        server_name,
        server_public_key,
        None,
    ))
    .await
    .map_err(|_| "Authentication / session activation timed out. Check the server and domain connectivity; over VPN, also check tunnel MTU and packet filtering.".to_string())?
    .map_err(|e| format!("Authentication / session activation failed: {e}"))?;

    Ok((connection_result, upgraded_framed))
}

fn build_client_connector(
    config: &RdpSessionConfig,
    client_addr: core::net::SocketAddr,
    local_clipboard_text: &Arc<Mutex<String>>,
    clipboard_msg_tx: &mpsc::UnboundedSender<ClipboardMessage>,
    emit: &Arc<dyn Fn(RdpWorkerEvent) + Send + Sync + 'static>,
) -> Result<ClientConnector, String> {
    let codecs = client_codecs_capabilities(&[]).map_err(|e| format!("Codec config error: {e}"))?;
    let bitmap = BitmapConfig {
        color_depth: 32,
        lossy_compression: true,
        codecs,
    };

    let enable_audio = matches!(config.audio_mode, AudioRedirectionMode::PlayOnDevice);

    let connector_config = ironrdp_connector::Config {
        credentials: Credentials::UsernamePassword {
            username: config.username.clone(),
            password: config.password.clone(),
        },
        domain: if config.domain.trim().is_empty() {
            None
        } else {
            Some(config.domain.trim().to_string())
        },
        enable_tls: config.enable_tls,
        enable_credssp: config.enable_nla,
        keyboard_type: KeyboardType::IbmEnhanced,
        keyboard_subtype: 0,
        keyboard_layout: 0x0409,
        keyboard_functional_keys_count: 12,
        ime_file_name: String::new(),
        dig_product_id: String::new(),
        desktop_size: DesktopSize {
            width: config.width.max(640),
            height: config.height.max(480),
        },
        desktop_scale_factor: config.scale_factor,
        bitmap: Some(bitmap),
        client_build: 26100,
        client_name: "UbuntuTouch-RDP".to_string(),
        client_dir: "C:\\Windows\\System32\\mstscax.dll".to_string(),
        platform: MajorPlatformType::UNIX,
        hardware_id: None,
        license_cache: None,
        enable_server_pointer: true,
        autologon: true,
        enable_audio_playback: enable_audio,
        request_data: None,
        pointer_software_rendering: true,
        multitransport_flags: None,
        compression_type: Some(CompressionType::K64),
        performance_flags: PerformanceFlags::default(),
        timezone_info: TimezoneInfo::default(),
        alternate_shell: String::new(),
        work_dir: String::new(),
    };

    let drdynvc = DrdynvcClient::new()
        .with_dynamic_channel(DisplayControlClient::new(|_| Ok(Vec::new())))
        .with_dynamic_channel(EchoClient::new());

    let mut connector = ClientConnector::new(connector_config, client_addr)
        .with_static_channel(drdynvc);

    if enable_audio {
        let emit_audio = Arc::clone(emit);
        let handler = UtRdpsndHandler::new(Arc::new(move |chunk| {
            emit_audio(RdpWorkerEvent::AudioChunk(chunk));
        }));
        connector =
            connector.with_static_channel(ironrdp_rdpsnd::client::Rdpsnd::new(Box::new(handler)));
    }

    if config.clipboard_redirection {
        let emit_clip = Arc::clone(emit);
        let clip_backend = UtClipboardBackend::new(
            config.temp_dir.clone(),
            Arc::clone(local_clipboard_text),
            clipboard_msg_tx.clone(),
            Arc::new(move |text| {
                emit_clip(RdpWorkerEvent::RemoteClipboardChanged { text });
            }),
        );
        connector.attach_static_channel(ironrdp_cliprdr::Cliprdr::new(Box::new(clip_backend)));
    }

    Ok(connector)
}

enum SessionLoopFlow {
    ReconnectWithNewSize { width: u16, height: u16 },
    TerminatedGracefully(GracefulDisconnectReason),
}

async fn drive_active_session(
    framed: UpgradedFramed,
    connection_result: ConnectionResult,
    framebuffer: &Arc<Mutex<SharedFrameBuffer>>,
    local_clipboard_text: &Arc<Mutex<String>>,
    clipboard_msg_tx: &mpsc::UnboundedSender<ClipboardMessage>,
    clipboard_msg_rx: &mut mpsc::UnboundedReceiver<ClipboardMessage>,
    cmd_rx: &mut mpsc::UnboundedReceiver<RdpCommand>,
    pending_commands: &mut VecDeque<RdpCommand>,
    emit: &Arc<dyn Fn(RdpWorkerEvent) + Send + Sync + 'static>,
) -> SessionResult<SessionLoopFlow> {
    let (mut reader, mut writer) = split_tokio_framed(framed);
    let desktop_size = connection_result.desktop_size;
    let mut image = DecodedImage::new(PixelFormat::RgbA32, desktop_size.width, desktop_size.height);
    let activation_factory = connection_result.activation_factory;

    let mut active_stage = ActiveStageBuilder {
        static_channels: connection_result.static_channels,
        user_channel_id: connection_result.user_channel_id,
        io_channel_id: connection_result.io_channel_id,
        message_channel_id: connection_result.message_channel_id,
        share_id: connection_result.share_id,
        compression_type: connection_result.compression_type,
        enable_server_pointer: connection_result.enable_server_pointer,
        pointer_software_rendering: connection_result.pointer_software_rendering,
    }
    .build();

    let mut frames_in_window = 0u32;
    let mut fps_window_start = tokio::time::Instant::now();
    let mut current_fps = 30u32;

    let reason = 'outer: loop {
        let outputs = tokio::select! {
            frame = reader.read_pdu() => {
                let (action, payload) = frame.map_err(|e| ironrdp_session::custom_err!("read PDU", e))?;
                active_stage.process(&mut image, action, &payload)?
            }
            Some(clip_msg) = clipboard_msg_rx.recv() => {
                process_clipboard_message(&mut active_stage, clip_msg)?
            }
            cmd = async {
                if let Some(command) = pending_commands.pop_front() {
                    Some(command)
                } else {
                    cmd_rx.recv().await
                }
            } => {
                let Some(cmd) = cmd else {
                    break 'outer GracefulDisconnectReason::UserInitiated;
                };
                match cmd {
                    RdpCommand::Disconnect => {
                        active_stage.graceful_shutdown()?
                    }
                    RdpCommand::FastPathInput(events) => {
                        active_stage.process_fastpath_input(&mut image, &events)?
                    }
                    RdpCommand::ResizeDesktop { width, height, scale_factor } => {
                        let (adj_w, adj_h) = MonitorLayoutEntry::adjust_display_size(u32::from(width), u32::from(height));
                        if let Some(res_frame) = active_stage.encode_resize(adj_w, adj_h, Some(scale_factor), None) {
                            vec![ActiveStageOutput::ResponseFrame(res_frame?)]
                        } else {
                            return Ok(SessionLoopFlow::ReconnectWithNewSize {
                                width: u16::try_from(adj_w).unwrap_or(1280),
                                height: u16::try_from(adj_h).unwrap_or(720),
                            });
                        }
                    }
                    RdpCommand::SetLocalClipboardText(text) => {
                        if let Ok(mut guard) = local_clipboard_text.lock() {
                            *guard = text;
                        }
                        let _ = clipboard_msg_tx.send(ClipboardMessage::SendInitiateCopy(
                            UtClipboardBackend::advertise_formats(),
                        ));
                        Vec::new()
                    }
                }
            }
        };

        for out in outputs {
            match out {
                ActiveStageOutput::ResponseFrame(frame) => {
                    if !frame.is_empty() {
                        writer
                            .write_all(&frame)
                            .await
                            .map_err(|e| ironrdp_session::custom_err!("write response frame", e))?;
                    }
                }
                ActiveStageOutput::GraphicsUpdate(region) => {
                    frames_in_window += 1;
                    let elapsed = fps_window_start.elapsed();
                    if elapsed >= Duration::from_secs(1) {
                        current_fps = frames_in_window;
                        frames_in_window = 0;
                        fps_window_start = tokio::time::Instant::now();
                    }

                    let dirty = DirtyRect {
                        x: region.left,
                        y: region.top,
                        width: region.width(),
                        height: region.height(),
                    };
                    if let Ok(mut fb) = framebuffer.lock() {
                        fb.update_region_rgba(image.width(), image.height(), image.data(), dirty);
                    }
                    emit(RdpWorkerEvent::FrameUpdated {
                        dirty,
                        fps: current_fps,
                    });
                }
                ActiveStageOutput::PointerPosition { x, y } => {
                    if let Ok(mut fb) = framebuffer.lock() {
                        fb.set_cursor_position(x, y);
                    }
                }
                ActiveStageOutput::PointerHidden => {
                    if let Ok(mut fb) = framebuffer.lock() {
                        fb.set_cursor_visible(false);
                    }
                }
                ActiveStageOutput::PointerDefault | ActiveStageOutput::PointerBitmap(_) => {
                    if let Ok(mut fb) = framebuffer.lock() {
                        fb.set_cursor_visible(true);
                    }
                }
                ActiveStageOutput::DeactivateAll => {
                    let mut connection_activation = activation_factory.create();
                    let mut buf = WriteBuf::new();
                    loop {
                        let written = single_sequence_step_read(
                            &mut reader,
                            &mut connection_activation,
                            &mut buf,
                        )
                        .await
                        .map_err(|e| {
                            ironrdp_session::custom_err!("deactivation-reactivation step", e)
                        })?;
                        if written.size().is_some() {
                            writer.write_all(buf.filled()).await.map_err(|e| {
                                ironrdp_session::custom_err!("write reactivation step", e)
                            })?;
                        }
                        if let ConnectionActivationState::Finalized {
                            desktop_size,
                            share_id,
                            enable_server_pointer,
                            pointer_software_rendering,
                        } = connection_activation.connection_activation_state()
                        {
                            image = DecodedImage::new(
                                PixelFormat::RgbA32,
                                desktop_size.width,
                                desktop_size.height,
                            );
                            if let Ok(mut fb) = framebuffer.lock() {
                                fb.resize_clear(desktop_size.width, desktop_size.height);
                            }
                            emit(RdpWorkerEvent::DesktopResized {
                                width: desktop_size.width,
                                height: desktop_size.height,
                            });
                            active_stage.set_fastpath_processor(
                                fast_path::ProcessorBuilder {
                                    io_channel_id: connection_activation.io_channel_id(),
                                    user_channel_id: connection_activation.user_channel_id(),
                                    share_id,
                                    enable_server_pointer,
                                    pointer_software_rendering,
                                    bulk_decompressor: None,
                                }
                                .build(),
                            );
                            active_stage.set_share_id(share_id);
                            active_stage.set_enable_server_pointer(enable_server_pointer);
                            break;
                        }
                    }
                }
                ActiveStageOutput::Terminate(reason) => break 'outer reason,
                ActiveStageOutput::MultitransportRequest(_) | ActiveStageOutput::AutoDetect(_) => {}
            }
        }
    };

    Ok(SessionLoopFlow::TerminatedGracefully(reason))
}

fn process_clipboard_message(
    active_stage: &mut ironrdp_session::ActiveStage,
    msg: ClipboardMessage,
) -> SessionResult<Vec<ActiveStageOutput>> {
    let Some(cliprdr) = active_stage.get_svc_processor_mut::<ironrdp_cliprdr::CliprdrClient>()
    else {
        return Ok(Vec::new());
    };
    let svc_msgs = match msg {
        ClipboardMessage::SendInitiateCopy(formats) => cliprdr
            .initiate_copy(&formats)
            .map_err(|e| ironrdp_session::custom_err!("CLIPRDR initiate_copy", e))?,
        ClipboardMessage::SendFormatData(resp) => cliprdr
            .submit_format_data(resp)
            .map_err(|e| ironrdp_session::custom_err!("CLIPRDR submit_format_data", e))?,
        ClipboardMessage::SendInitiatePaste(fmt) => cliprdr
            .initiate_paste(fmt)
            .map_err(|e| ironrdp_session::custom_err!("CLIPRDR initiate_paste", e))?,
        ClipboardMessage::SendFileContentsRequest(req) => cliprdr
            .request_file_contents(req)
            .map_err(|e| ironrdp_session::custom_err!("CLIPRDR request_file_contents", e))?,
        ClipboardMessage::SendFileContentsResponse(resp) => cliprdr
            .submit_file_contents(resp)
            .map_err(|e| ironrdp_session::custom_err!("CLIPRDR submit_file_contents", e))?,
        ClipboardMessage::SendInitiateFileCopy(files) => cliprdr
            .initiate_file_copy(files)
            .map_err(|e| ironrdp_session::custom_err!("CLIPRDR initiate_file_copy", e))?,
        ClipboardMessage::Error(_) => return Ok(Vec::new()),
    };
    let frame = active_stage.process_svc_processor_messages(svc_msgs)?;
    if frame.is_empty() {
        Ok(Vec::new())
    } else {
        Ok(vec![ActiveStageOutput::ResponseFrame(frame)])
    }
}

struct TokioNetworkClient;

impl NetworkClient for TokioNetworkClient {
    async fn send(
        &mut self,
        network_request: &sspi::generator::NetworkRequest,
    ) -> ConnectorResult<Vec<u8>> {
        match &network_request.protocol {
            sspi::network_client::NetworkProtocol::Tcp => {
                send_kdc_tcp(&network_request.url, &network_request.data).await
            }
            sspi::network_client::NetworkProtocol::Udp => {
                send_kdc_udp(&network_request.url, &network_request.data).await
            }
            _ => Err(general_err!(
                "KDC HTTP proxy not configured for direct NLA connection"
            )),
        }
    }
}

async fn send_kdc_tcp(url: &Url, data: &[u8]) -> ConnectorResult<Vec<u8>> {
    let addr = format!(
        "{}:{}",
        url.host_str().unwrap_or_default(),
        url.port().unwrap_or(88)
    );
    let mut stream = TcpStream::connect(addr)
        .await
        .map_err(|e| SspiError::new(SspiErrorKind::NoAuthenticatingAuthority, format!("{e:?}")))
        .map_err(|e| custom_err!("KDC TCP connect", e))?;
    stream
        .write_all(data)
        .await
        .map_err(|e| custom_err!("KDC TCP write", e))?;
    let len = stream
        .read_u32()
        .await
        .map_err(|e| custom_err!("KDC TCP read len", e))?;
    let len_usize = usize::try_from(len).map_err(|_| general_err!("KDC TCP length overflow"))?;
    let mut buf = vec![0u8; len_usize + 4];
    buf[0..4].copy_from_slice(&len.to_be_bytes());
    stream
        .read_exact(&mut buf[4..])
        .await
        .map_err(|e| custom_err!("KDC TCP read body", e))?;
    Ok(buf)
}

async fn send_kdc_udp(url: &Url, data: &[u8]) -> ConnectorResult<Vec<u8>> {
    let host = url
        .host_str()
        .unwrap_or_default()
        .trim_start_matches('[')
        .trim_end_matches(']');
    let addresses = transport::resolve(host, url.port().unwrap_or(88))
        .await
        .map_err(|e| custom_err!("KDC UDP DNS", std::io::Error::other(e)))?;
    let mut last_error = std::io::Error::other("no reachable KDC UDP address");
    for address in addresses {
        let result = tokio::time::timeout(Duration::from_secs(5), async {
            // Loopback binding prevented remote/domain authentication. Let the
            // system select the LAN/VPN source address, in the destination family.
            let bind_ip = if address.is_ipv6() {
                IpAddr::V6(Ipv6Addr::UNSPECIFIED)
            } else {
                IpAddr::V4(Ipv4Addr::UNSPECIFIED)
            };
            let socket = UdpSocket::bind((bind_ip, 0)).await?;
            // Connected UDP accepts replies only from this KDC endpoint.
            socket.connect(address).await?;
            socket.send(data).await?;
            let mut buf = vec![0u8; 48_000];
            let n = socket.recv(&mut buf).await?;
            let mut reply = Vec::with_capacity(n + 4);
            reply.extend_from_slice(&(n as u32).to_be_bytes());
            reply.extend_from_slice(&buf[..n]);
            Ok::<_, std::io::Error>(reply)
        })
        .await;
        match result {
            Ok(Ok(reply)) => return Ok(reply),
            Ok(Err(error)) => last_error = error,
            Err(_) => {
                last_error = std::io::Error::new(
                    std::io::ErrorKind::TimedOut,
                    format!("KDC UDP {address} timed out"),
                )
            }
        }
    }
    Err(custom_err!("KDC UDP exchange", last_error))
}

#[cfg(test)]
mod connection_tests {
    use super::*;
    use tokio::net::TcpListener;

    #[tokio::test]
    async fn cancel_stops_a_worker_while_server_stalls_negotiation() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let config = RdpSessionConfig {
            profile_id: "cancel-test".to_string(),
            friendly_name: "Test".to_string(),
            hostname: "127.0.0.1".to_string(),
            port: listener.local_addr().unwrap().port(),
            username: "test".to_string(),
            password: String::new(),
            domain: String::new(),
            width: 800,
            height: 600,
            scale_factor: 100,
            enable_tls: true,
            enable_nla: true,
            clipboard_redirection: false,
            audio_mode: AudioRedirectionMode::Disabled,
            temp_dir: String::new(),
        };
        let (cmd_tx, cmd_rx) = mpsc::unbounded_channel();
        let (_cert_tx, cert_rx) = oneshot::channel();
        let events = Arc::new(Mutex::new(Vec::new()));
        let captured = Arc::clone(&events);
        let worker = run_session_lifecycle(
            config,
            SharedFrameBuffer::new_shared(800, 600),
            Arc::new(Mutex::new(CertStore::default())),
            cmd_rx,
            cert_rx,
            Arc::new(move |event| captured.lock().unwrap().push(event)),
        );
        let cancel_after_request = async {
            let (mut peer, _) = listener.accept().await.unwrap();
            let mut request = [0; 512];
            peer.read(&mut request).await.unwrap();
            cmd_tx.send(RdpCommand::Disconnect).unwrap();
            // Keep the peer open, so only cancellation can finish the worker.
            tokio::time::sleep(Duration::from_millis(100)).await;
        };
        tokio::time::timeout(Duration::from_secs(2), async {
            tokio::join!(worker, cancel_after_request);
        })
        .await
        .expect("cancel must interrupt negotiation");
        assert!(matches!(
            events.lock().unwrap().last(),
            Some(RdpWorkerEvent::SessionEnded {
                is_error: false,
                ..
            })
        ));
    }

    #[tokio::test]
    async fn kdc_udp_supports_ipv6_and_non_loopback_routes() {
        // Discover this machine's routed address without sending any packets.
        // A loopback-only socket would fail to reach the fake KDC on that address.
        let route = std::net::UdpSocket::bind("0.0.0.0:0").unwrap();
        route.connect("192.0.2.1:88").unwrap();
        let routed_ip = route.local_addr().unwrap().ip();
        assert!(!routed_ip.is_loopback());
        for ip in [routed_ip, IpAddr::V6(Ipv6Addr::LOCALHOST)] {
            let server = UdpSocket::bind((ip, 0)).await.unwrap();
            let address = server.local_addr().unwrap();
            let response = tokio::spawn(async move {
                let mut request = [0; 128];
                let (length, source) = server.recv_from(&mut request).await.unwrap();
                assert_eq!(&request[..length], b"kerberos request");
                assert_eq!(source.ip().is_loopback(), ip.is_loopback());
                server.send_to(b"test response", source).await.unwrap();
            });
            let url = Url::parse(&format!("udp://{address}")).unwrap();
            let result = tokio::time::timeout(
                Duration::from_secs(2),
                send_kdc_udp(&url, b"kerberos request"),
            )
            .await
            .unwrap()
            .unwrap();
            assert_eq!(&result[..4], &(13u32).to_be_bytes());
            assert_eq!(&result[4..], b"test response");
            response.await.unwrap();
        }
    }
}
