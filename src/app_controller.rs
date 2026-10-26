use std::sync::{Arc, Mutex};

use serde_json::{json, Value};

use crate::models::account::{current_epoch_secs, split_domain_username};
use crate::models::{
    parse_host_port, AudioRedirectionMode, CertStore, CertTrustDecision, PcProfile, ResolutionMode,
    TouchInputMode, UserAccount,
};
use crate::rdp::canvas_item::SharedFrameBuffer;
use crate::rdp::input_mapper::{InputMapper, MouseButtonKind};
use crate::rdp::session_worker::{
    spawn_rdp_session, RdpCommand, RdpSessionConfig, RdpSessionHandle, RdpWorkerEvent, SessionStage,
};
use crate::storage::{AppSettings, CredentialVault, StorageDatabase};

pub type UiEventCallback = Arc<dyn Fn(&str, &[u8]) + Send + Sync + 'static>;

pub struct AppController {
    db: StorageDatabase,
    vault: CredentialVault,
    profiles: Mutex<Vec<PcProfile>>,
    accounts: Mutex<Vec<UserAccount>>,
    cert_store: Arc<Mutex<CertStore>>,
    settings: Mutex<AppSettings>,
    framebuffer: Arc<Mutex<SharedFrameBuffer>>,
    input_mapper: Mutex<InputMapper>,
    active_session: Mutex<Option<Arc<RdpSessionHandle>>>,
    active_profile_id: Mutex<String>,
    active_touch_mode: Mutex<TouchInputMode>,
    session_stage: Mutex<SessionStage>,
    ui_callback: UiEventCallback,
}

impl AppController {
    pub fn new(
        db: StorageDatabase,
        vault: CredentialVault,
        ui_callback: UiEventCallback,
    ) -> Arc<Self> {
        let mut profiles = db.load_profiles();
        let accounts = db.load_accounts();
        let cert_store = db.load_cert_store();
        let settings = db.load_settings();

        if profiles.is_empty() {
            if let Ok(mut demo_pc) = PcProfile::new("demo.local:3389", "Windows 11 Demo PC") {
                demo_pc.group_name = "Quick Try".to_string();
                demo_pc.favorite = true;
                profiles.push(demo_pc);
                let _ = db.save_profiles(&profiles);
            }
        }

        let initial_touch = settings.default_touch_mode;

        Arc::new(Self {
            db,
            vault,
            profiles: Mutex::new(profiles),
            accounts: Mutex::new(accounts),
            cert_store: Arc::new(Mutex::new(cert_store)),
            settings: Mutex::new(settings),
            framebuffer: SharedFrameBuffer::new_shared(1280, 720),
            input_mapper: Mutex::new(InputMapper::new(1280, 720)),
            active_session: Mutex::new(None),
            active_profile_id: Mutex::new(String::new()),
            active_touch_mode: Mutex::new(initial_touch),
            session_stage: Mutex::new(SessionStage::Disconnected),
            ui_callback,
        })
    }

    pub fn framebuffer(&self) -> Arc<Mutex<SharedFrameBuffer>> {
        Arc::clone(&self.framebuffer)
    }

    pub fn emit_state_snapshot(&self) {
        let profiles = self.profiles.lock().map(|p| p.clone()).unwrap_or_default();
        let accounts = self.accounts.lock().map(|a| a.clone()).unwrap_or_default();
        let settings = self.settings.lock().map(|s| s.clone()).unwrap_or_default();
        let certs = self
            .cert_store
            .lock()
            .map(|c| c.list_known_hosts())
            .unwrap_or_default();
        let mapper = self
            .input_mapper
            .lock()
            .map(|m| m.clone())
            .unwrap_or_default();
        let active_id = self
            .active_profile_id
            .lock()
            .map(|s| s.clone())
            .unwrap_or_default();
        let touch_mode = self
            .active_touch_mode
            .lock()
            .map(|t| *t)
            .unwrap_or(TouchInputMode::MousePointer);
        let stage = self
            .session_stage
            .lock()
            .map(|s| s.clone())
            .unwrap_or(SessionStage::Disconnected);

        let profiles_json: Vec<Value> = profiles
            .iter()
            .map(|p| {
                let account_label = match &p.account_id {
                    Some(acc_id) => accounts
                        .iter()
                        .find(|a| &a.id == acc_id)
                        .map(|a| a.display_name.clone())
                        .unwrap_or_else(|| "Ask every time".to_string()),
                    None => "Ask every time".to_string(),
                };
                json!({
                    "id": p.id,
                    "hostname": p.hostname,
                    "port": p.port,
                    "address": p.address_string(),
                    "friendlyName": p.friendly_name,
                    "displayTitle": p.display_title(),
                    "accountId": p.account_id.clone().unwrap_or_default(),
                    "accountLabel": account_label,
                    "resolutionPreset": p.resolution_mode.preset_key(),
                    "resolutionLabel": p.resolution_mode.display_label(),
                    "scaleFactor": p.scale_factor,
                    "clipboardRedirection": p.clipboard_redirection,
                    "audioMode": p.audio_mode.as_key(),
                    "defaultTouchMode": p.default_touch_mode.as_key(),
                    "enableNla": p.enable_nla,
                    "enableTls": p.enable_tls,
                    "groupName": p.group_name,
                    "lastConnectedEpoch": p.last_connected_epoch.unwrap_or(0),
                    "thumbnailPath": p.thumbnail_path.clone().unwrap_or_default(),
                    "favorite": p.favorite,
                    "isDemo": p.hostname.eq_ignore_ascii_case("demo.local") || p.hostname.eq_ignore_ascii_case("demo"),
                })
            })
            .collect();

        let accounts_json: Vec<Value> = accounts
            .iter()
            .map(|a| {
                json!({
                    "id": a.id,
                    "displayName": a.display_name,
                    "username": a.username,
                    "domain": a.domain,
                    "qualifiedUsername": a.qualified_username(),
                    "hasSavedPassword": a.has_saved_password,
                })
            })
            .collect();

        let certs_json: Vec<Value> = certs
            .iter()
            .map(|c| {
                json!({
                    "hostPort": c.host_port,
                    "subjectCn": c.subject_cn,
                    "issuerCn": c.issuer_cn,
                    "validFrom": c.valid_from,
                    "validUntil": c.valid_until,
                    "sha256Fingerprint": c.sha256_fingerprint,
                    "trustedAtEpoch": c.trusted_at_epoch,
                })
            })
            .collect();

        let payload = json!({
            "type": "state_snapshot",
            "appVersion": env!("CARGO_PKG_VERSION"),
            "appArchitecture": match std::env::consts::ARCH {
                "aarch64" => "arm64",
                "x86_64" => "amd64",
                "arm" => "armhf",
                other => other,
            },
            "appFramework": crate::storage::database::APP_FRAMEWORK,
            "profiles": profiles_json,
            "accounts": accounts_json,
            "knownCerts": certs_json,
            "settings": {
                "themeMode": settings.theme_mode,
                "defaultResolution": settings.default_resolution.preset_key(),
                "defaultScaleFactor": settings.default_scale_factor,
                "defaultTouchMode": settings.default_touch_mode.as_key(),
                "defaultAudioMode": settings.default_audio_mode.as_key(),
                "defaultClipboardEnabled": settings.default_clipboard_enabled,
                "trackpadSpeedPercent": settings.trackpad_speed_percent,
                "showStatsOverlay": settings.show_stats_overlay,
                "strictCertCheck": settings.strict_cert_check,
                "autoCheckUpdates": settings.auto_check_updates,
                "skippedUpdateVersion": settings.skipped_update_version,
                "lastUpdateCheckEpoch": settings.last_update_check_epoch,
            },
            "session": {
                "activeProfileId": active_id,
                "stage": stage.as_str(),
                "stageLabel": stage.human_label(),
                "touchMode": touch_mode.as_key(),
                "cursorX": mapper.cursor_position().0,
                "cursorY": mapper.cursor_position().1,
                "ctrlState": mapper.ctrl,
                "altState": mapper.alt,
                "shiftState": mapper.shift,
                "winState": mapper.win,
            }
        });

        self.emit_json(&payload);
    }

    pub fn dispatch_action(self: &Arc<Self>, action_json: &str) -> Result<(), String> {
        let v: Value =
            serde_json::from_str(action_json).map_err(|e| format!("Invalid action JSON: {e}"))?;
        let action = v
            .get("action")
            .and_then(Value::as_str)
            .unwrap_or_default();

        match action {
            "init" | "refresh" => {
                self.emit_state_snapshot();
            }
            "save_pc" => {
                self.handle_save_pc(&v)?;
                self.emit_state_snapshot();
            }
            "delete_pc" => {
                let id = v.get("id").and_then(Value::as_str).unwrap_or_default();
                self.handle_delete_pc(id)?;
                self.emit_state_snapshot();
            }
            "duplicate_pc" => {
                let id = v.get("id").and_then(Value::as_str).unwrap_or_default();
                self.handle_duplicate_pc(id)?;
                self.emit_state_snapshot();
            }
            "toggle_favorite_pc" => {
                let id = v.get("id").and_then(Value::as_str).unwrap_or_default();
                self.handle_toggle_favorite(id)?;
                self.emit_state_snapshot();
            }
            "clear_thumbnail" => {
                let id = v.get("id").and_then(Value::as_str).unwrap_or_default();
                self.handle_clear_thumbnail(id)?;
                self.emit_state_snapshot();
            }
            "save_account" => {
                self.handle_save_account(&v)?;
                self.emit_state_snapshot();
            }
            "delete_account" => {
                let id = v.get("id").and_then(Value::as_str).unwrap_or_default();
                self.handle_delete_account(id)?;
                self.emit_state_snapshot();
            }
            "remove_known_cert" => {
                let host_port = v
                    .get("hostPort")
                    .and_then(Value::as_str)
                    .unwrap_or_default();
                if let Ok(mut store) = self.cert_store.lock() {
                    store.remove_host(host_port);
                    let _ = self.db.save_cert_store(&store);
                }
                self.emit_state_snapshot();
            }
            "save_settings" => {
                self.handle_save_settings(&v)?;
                self.emit_state_snapshot();
            }
            "connect_pc" => {
                self.handle_connect_pc(&v)?;
            }
            "disconnect_session" => {
                self.handle_disconnect_session();
            }
            "respond_certificate" => {
                let decision_str = v
                    .get("decision")
                    .and_then(Value::as_str)
                    .unwrap_or("reject");
                let decision = match decision_str {
                    "trust_always" => CertTrustDecision::TrustAlways,
                    "trust_once" => CertTrustDecision::TrustOnce,
                    _ => CertTrustDecision::Reject,
                };
                if let Ok(guard) = self.active_session.lock() {
                    if let Some(handle) = guard.as_ref() {
                        handle.respond_certificate(decision);
                    }
                }
                if decision == CertTrustDecision::TrustAlways {
                    if let Ok(store) = self.cert_store.lock() {
                        let _ = self.db.save_cert_store(&store);
                    }
                }
                self.emit_state_snapshot();
            }
            "set_touch_mode" => {
                let mode = TouchInputMode::from_key(
                    v.get("mode").and_then(Value::as_str).unwrap_or("mouse_pointer"),
                );
                if let Ok(mut guard) = self.active_touch_mode.lock() {
                    *guard = mode;
                }
                self.emit_state_snapshot();
            }
            "trackpad_move" => {
                let dx = v.get("dx").and_then(Value::as_f64).unwrap_or(0.0) as f32;
                let dy = v.get("dy").and_then(Value::as_f64).unwrap_or(0.0) as f32;
                let speed = self
                    .settings
                    .lock()
                    .map(|s| s.trackpad_speed_percent)
                    .unwrap_or(100);
                let (events, pos) = {
                    let mut mapper = self.input_mapper.lock().map_err(|e| e.to_string())?;
                    let ev = mapper.move_relative(dx, dy, speed);
                    (ev, mapper.cursor_position())
                };
                self.send_fastpath_events(events.into_iter().collect());
                self.emit_json(&json!({
                    "type": "cursor_moved",
                    "x": pos.0,
                    "y": pos.1,
                }));
            }
            "pointer_move_abs" => {
                let x = v.get("x").and_then(Value::as_u64).unwrap_or(0) as u16;
                let y = v.get("y").and_then(Value::as_u64).unwrap_or(0) as u16;
                let (events, pos) = {
                    let mut mapper = self.input_mapper.lock().map_err(|e| e.to_string())?;
                    let ev = mapper.move_absolute(x, y);
                    (ev, mapper.cursor_position())
                };
                self.send_fastpath_events(events.into_iter().collect());
                self.emit_json(&json!({
                    "type": "cursor_moved",
                    "x": pos.0,
                    "y": pos.1,
                }));
            }
            "mouse_button" => {
                let btn = MouseButtonKind::from_qt_button(
                    v.get("button").and_then(Value::as_i64).unwrap_or(1) as i32,
                );
                let pressed = v.get("pressed").and_then(Value::as_bool).unwrap_or(false);
                if let (Some(x), Some(y)) = (
                    v.get("x").and_then(Value::as_u64),
                    v.get("y").and_then(Value::as_u64),
                ) {
                    let move_ev = self
                        .input_mapper
                        .lock()
                        .map_err(|e| e.to_string())?
                        .move_absolute(x as u16, y as u16);
                    self.send_fastpath_events(move_ev.into_iter().collect());
                }
                let events = self
                    .input_mapper
                    .lock()
                    .map_err(|e| e.to_string())?
                    .mouse_button(btn, pressed);
                self.send_fastpath_events(events.into_iter().collect());
            }
            "mouse_click" => {
                let btn = MouseButtonKind::from_qt_button(
                    v.get("button").and_then(Value::as_i64).unwrap_or(1) as i32,
                );
                let double_click = v
                    .get("doubleClick")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                if let (Some(x), Some(y)) = (
                    v.get("x").and_then(Value::as_u64),
                    v.get("y").and_then(Value::as_u64),
                ) {
                    let move_ev = self
                        .input_mapper
                        .lock()
                        .map_err(|e| e.to_string())?
                        .move_absolute(x as u16, y as u16);
                    self.send_fastpath_events(move_ev.into_iter().collect());
                }
                let events = self
                    .input_mapper
                    .lock()
                    .map_err(|e| e.to_string())?
                    .mouse_click(btn, double_click);
                self.send_fastpath_events(events.into_iter().collect());
            }
            "mouse_scroll" => {
                let v_delta = v.get("vertical").and_then(Value::as_i64).unwrap_or(0) as i16;
                let h_delta = v.get("horizontal").and_then(Value::as_i64).unwrap_or(0) as i16;
                let events = self
                    .input_mapper
                    .lock()
                    .map_err(|e| e.to_string())?
                    .mouse_scroll(v_delta, h_delta);
                self.send_fastpath_events(events.into_iter().collect());
            }
            "toggle_modifier" => {
                let modifier = v.get("modifier").and_then(Value::as_str).unwrap_or_default();
                if let Ok(mut mapper) = self.input_mapper.lock() {
                    mapper.toggle_sticky_modifier(modifier);
                }
                self.emit_state_snapshot();
            }
            "send_virtual_key" => {
                let key = v.get("key").and_then(Value::as_str).unwrap_or_default();
                let events = self
                    .input_mapper
                    .lock()
                    .map_err(|e| e.to_string())?
                    .send_virtual_key(key);
                self.send_fastpath_events(events);
                self.emit_state_snapshot();
            }
            "send_qt_key" => {
                let qt_key = v.get("qtKey").and_then(Value::as_i64).unwrap_or(0) as i32;
                let text = v.get("text").and_then(Value::as_str).unwrap_or_default();
                let pressed = v.get("pressed").and_then(Value::as_bool).unwrap_or(true);
                let events = self
                    .input_mapper
                    .lock()
                    .map_err(|e| e.to_string())?
                    .map_qt_key(qt_key, text, pressed);
                self.send_fastpath_events(events);
                self.emit_state_snapshot();
            }
            "send_chord" => {
                let chord = v.get("chord").and_then(Value::as_str).unwrap_or_default();
                let events = self
                    .input_mapper
                    .lock()
                    .map_err(|e| e.to_string())?
                    .send_chord(chord);
                self.send_fastpath_events(events);
                self.emit_state_snapshot();
            }
            "resize_session" => {
                let w = v.get("width").and_then(Value::as_u64).unwrap_or(1280) as u16;
                let h = v.get("height").and_then(Value::as_u64).unwrap_or(720) as u16;
                let scale = v.get("scaleFactor").and_then(Value::as_u64).unwrap_or(100) as u32;
                if let Ok(guard) = self.active_session.lock() {
                    if let Some(handle) = guard.as_ref() {
                        handle.send_command(RdpCommand::ResizeDesktop {
                            width: w & !1,
                            height: h & !1,
                            scale_factor: scale,
                        });
                    }
                }
            }
            "set_local_clipboard" => {
                let text = v.get("text").and_then(Value::as_str).unwrap_or_default();
                if let Ok(guard) = self.active_session.lock() {
                    if let Some(handle) = guard.as_ref() {
                        handle.send_command(RdpCommand::SetLocalClipboardText(text.to_string()));
                    }
                }
            }
            _ => {}
        }
        Ok(())
    }

    fn handle_save_pc(&self, v: &Value) -> Result<(), String> {
        let host_input = v
            .get("hostInput")
            .and_then(Value::as_str)
            .unwrap_or_default();
        let (hostname, port) = parse_host_port(host_input)?;
        let friendly_name = v
            .get("friendlyName")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .trim()
            .to_string();
        let account_id = v
            .get("accountId")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(String::from);
        let resolution_mode = ResolutionMode::from_preset_key(
            v.get("resolutionPreset")
                .and_then(Value::as_str)
                .unwrap_or("dynamic"),
        );
        let scale_factor = v
            .get("scaleFactor")
            .and_then(Value::as_u64)
            .unwrap_or(100) as u32;
        let clipboard_redirection = v
            .get("clipboardRedirection")
            .and_then(Value::as_bool)
            .unwrap_or(true);
        let audio_mode = AudioRedirectionMode::from_key(
            v.get("audioMode")
                .and_then(Value::as_str)
                .unwrap_or("play_on_device"),
        );
        let default_touch_mode = TouchInputMode::from_key(
            v.get("defaultTouchMode")
                .and_then(Value::as_str)
                .unwrap_or("mouse_pointer"),
        );
        let enable_nla = v.get("enableNla").and_then(Value::as_bool).unwrap_or(true);
        let enable_tls = v.get("enableTls").and_then(Value::as_bool).unwrap_or(true);
        let group_name = v
            .get("groupName")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .unwrap_or("Saved PCs")
            .to_string();

        let existing_id = v
            .get("id")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|s| !s.is_empty());

        let mut profiles = self.profiles.lock().map_err(|e| e.to_string())?;
        if let Some(id) = existing_id {
            if let Some(pc) = profiles.iter_mut().find(|p| p.id == id) {
                pc.hostname = hostname;
                pc.port = port;
                pc.friendly_name = friendly_name;
                pc.account_id = account_id;
                pc.resolution_mode = resolution_mode;
                pc.scale_factor = scale_factor;
                pc.clipboard_redirection = clipboard_redirection;
                pc.audio_mode = audio_mode;
                pc.default_touch_mode = default_touch_mode;
                pc.enable_nla = enable_nla;
                pc.enable_tls = enable_tls;
                pc.group_name = group_name;
            }
        } else {
            let mut pc = PcProfile::new(&format!("{hostname}:{port}"), &friendly_name)?;
            pc.account_id = account_id;
            pc.resolution_mode = resolution_mode;
            pc.scale_factor = scale_factor;
            pc.clipboard_redirection = clipboard_redirection;
            pc.audio_mode = audio_mode;
            pc.default_touch_mode = default_touch_mode;
            pc.enable_nla = enable_nla;
            pc.enable_tls = enable_tls;
            pc.group_name = group_name;
            profiles.push(pc);
        }
        self.db.save_profiles(&profiles)
    }

    fn handle_delete_pc(&self, id: &str) -> Result<(), String> {
        let mut profiles = self.profiles.lock().map_err(|e| e.to_string())?;
        profiles.retain(|p| p.id != id);
        let thumb = self.db.thumbnail_path_for(id);
        if thumb.exists() {
            let _ = std::fs::remove_file(thumb);
        }
        self.db.save_profiles(&profiles)
    }

    fn handle_duplicate_pc(&self, id: &str) -> Result<(), String> {
        let mut profiles = self.profiles.lock().map_err(|e| e.to_string())?;
        let Some(orig) = profiles.iter().find(|p| p.id == id).cloned() else {
            return Err("PC profile not found".to_string());
        };
        let mut copy = orig;
        copy.id = uuid::Uuid::new_v4().to_string();
        copy.friendly_name = format!("{} (Copy)", copy.display_title());
        copy.last_connected_epoch = None;
        copy.thumbnail_path = None;
        profiles.push(copy);
        self.db.save_profiles(&profiles)
    }

    fn handle_toggle_favorite(&self, id: &str) -> Result<(), String> {
        let mut profiles = self.profiles.lock().map_err(|e| e.to_string())?;
        if let Some(pc) = profiles.iter_mut().find(|p| p.id == id) {
            pc.favorite = !pc.favorite;
        }
        self.db.save_profiles(&profiles)
    }

    fn handle_clear_thumbnail(&self, id: &str) -> Result<(), String> {
        let mut profiles = self.profiles.lock().map_err(|e| e.to_string())?;
        if let Some(pc) = profiles.iter_mut().find(|p| p.id == id) {
            pc.thumbnail_path = None;
        }
        let thumb = self.db.thumbnail_path_for(id);
        if thumb.exists() {
            let _ = std::fs::remove_file(thumb);
        }
        self.db.save_profiles(&profiles)
    }

    fn handle_save_account(&self, v: &Value) -> Result<(), String> {
        let username = v
            .get("username")
            .and_then(Value::as_str)
            .unwrap_or_default();
        let domain = v.get("domain").and_then(Value::as_str).unwrap_or_default();
        let display_name = v
            .get("displayName")
            .and_then(Value::as_str)
            .unwrap_or_default();
        let password = v
            .get("password")
            .and_then(Value::as_str)
            .unwrap_or_default();
        let existing_id = v
            .get("id")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|s| !s.is_empty());

        let mut accounts = self.accounts.lock().map_err(|e| e.to_string())?;
        if let Some(id) = existing_id {
            if let Some(acct) = accounts.iter_mut().find(|a| a.id == id) {
                let (parsed_dom, parsed_user) = split_domain_username(username);
                if parsed_user.is_empty() {
                    return Err("Username cannot be empty".to_string());
                }
                acct.username = parsed_user;
                acct.domain = if !domain.trim().is_empty() {
                    domain.trim().to_string()
                } else {
                    parsed_dom
                };
                if !display_name.trim().is_empty() {
                    acct.display_name = display_name.trim().to_string();
                } else {
                    acct.display_name = acct.qualified_username();
                }
                if !password.is_empty() {
                    self.vault.set_password(&acct.id, password)?;
                    acct.has_saved_password = true;
                }
                acct.updated_at_epoch = current_epoch_secs();
            }
        } else {
            let mut acct = UserAccount::new(username, domain, display_name)?;
            if !password.is_empty() {
                self.vault.set_password(&acct.id, password)?;
                acct.has_saved_password = true;
            }
            accounts.push(acct);
        }
        self.db.save_accounts(&accounts)
    }

    fn handle_delete_account(&self, id: &str) -> Result<(), String> {
        let mut accounts = self.accounts.lock().map_err(|e| e.to_string())?;
        accounts.retain(|a| a.id != id);
        let _ = self.vault.delete_password(id);
        self.db.save_accounts(&accounts)?;

        let mut profiles = self.profiles.lock().map_err(|e| e.to_string())?;
        for pc in profiles.iter_mut() {
            if pc.account_id.as_deref() == Some(id) {
                pc.account_id = None;
            }
        }
        self.db.save_profiles(&profiles)
    }

    fn handle_save_settings(&self, v: &Value) -> Result<(), String> {
        let mut settings = self.settings.lock().map_err(|e| e.to_string())?;
        if let Some(theme) = v.get("themeMode").and_then(Value::as_str) {
            settings.theme_mode = theme.to_string();
        }
        if let Some(res) = v.get("defaultResolution").and_then(Value::as_str) {
            settings.default_resolution = ResolutionMode::from_preset_key(res);
        }
        if let Some(scale) = v.get("defaultScaleFactor").and_then(Value::as_u64) {
            settings.default_scale_factor = scale as u32;
        }
        if let Some(touch) = v.get("defaultTouchMode").and_then(Value::as_str) {
            settings.default_touch_mode = TouchInputMode::from_key(touch);
        }
        if let Some(audio) = v.get("defaultAudioMode").and_then(Value::as_str) {
            settings.default_audio_mode = AudioRedirectionMode::from_key(audio);
        }
        if let Some(clip) = v.get("defaultClipboardEnabled").and_then(Value::as_bool) {
            settings.default_clipboard_enabled = clip;
        }
        if let Some(speed) = v.get("trackpadSpeedPercent").and_then(Value::as_u64) {
            settings.trackpad_speed_percent = speed.clamp(25, 300) as u32;
        }
        if let Some(stats) = v.get("showStatsOverlay").and_then(Value::as_bool) {
            settings.show_stats_overlay = stats;
        }
        if let Some(strict) = v.get("strictCertCheck").and_then(Value::as_bool) {
            settings.strict_cert_check = strict;
        }
        if let Some(enabled) = v.get("autoCheckUpdates").and_then(Value::as_bool) {
            settings.auto_check_updates = enabled;
        }
        if let Some(version) = v.get("skippedUpdateVersion").and_then(Value::as_str) {
            settings.skipped_update_version = version.to_string();
        }
        if let Some(epoch) = v.get("lastUpdateCheckEpoch").and_then(Value::as_u64) {
            settings.last_update_check_epoch = epoch;
        }
        self.db.save_settings(&settings)
    }

    fn handle_connect_pc(self: &Arc<Self>, v: &Value) -> Result<(), String> {
        let profile_id = v
            .get("id")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        let viewport_w = v
            .get("viewportWidth")
            .and_then(Value::as_u64)
            .unwrap_or(1280) as u16;
        let viewport_h = v
            .get("viewportHeight")
            .and_then(Value::as_u64)
            .unwrap_or(720) as u16;
        let prompt_user = v
            .get("username")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .trim()
            .to_string();
        let prompt_pass = v
            .get("password")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        let prompt_domain = v
            .get("domain")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .trim()
            .to_string();

        let profile = {
            let profiles = self.profiles.lock().map_err(|e| e.to_string())?;
            profiles
                .iter()
                .find(|p| p.id == profile_id)
                .cloned()
                .ok_or_else(|| "PC profile not found".to_string())?
        };

        let is_demo = profile.hostname.eq_ignore_ascii_case("demo")
            || profile.hostname.eq_ignore_ascii_case("demo.local")
            || profile.hostname.eq_ignore_ascii_case("demo-pc");

        // Resolve credentials
        let (username, password, domain) = if !prompt_user.is_empty() {
            let (parsed_dom, parsed_user) = split_domain_username(&prompt_user);
            (
                parsed_user,
                prompt_pass,
                if !prompt_domain.is_empty() {
                    prompt_domain
                } else {
                    parsed_dom
                },
            )
        } else if let Some(acc_id) = &profile.account_id {
            let accounts = self.accounts.lock().map_err(|e| e.to_string())?;
            if let Some(acct) = accounts.iter().find(|a| &a.id == acc_id) {
                let saved_pw = self.vault.get_password(&acct.id).unwrap_or_default();
                if saved_pw.is_empty() && !is_demo {
                    self.emit_json(&json!({
                        "type": "credentials_required",
                        "profileId": profile.id,
                        "displayTitle": profile.display_title(),
                        "prefillUsername": acct.qualified_username(),
                    }));
                    return Ok(());
                }
                (acct.username.clone(), saved_pw, acct.domain.clone())
            } else if !is_demo {
                self.emit_json(&json!({
                    "type": "credentials_required",
                    "profileId": profile.id,
                    "displayTitle": profile.display_title(),
                    "prefillUsername": "",
                }));
                return Ok(());
            } else {
                ("ubuntu".to_string(), "demo".to_string(), String::new())
            }
        } else if !is_demo {
            self.emit_json(&json!({
                "type": "credentials_required",
                "profileId": profile.id,
                "displayTitle": profile.display_title(),
                "prefillUsername": "",
            }));
            return Ok(());
        } else {
            ("ubuntu".to_string(), "demo".to_string(), String::new())
        };

        // Disconnect any previous session first
        self.handle_disconnect_session();

        let (width, height) = profile
            .resolution_mode
            .resolve_dimensions(viewport_w, viewport_h);

        if let Ok(mut mapper) = self.input_mapper.lock() {
            *mapper = InputMapper::new(width, height);
        }
        if let Ok(mut tm) = self.active_touch_mode.lock() {
            *tm = profile.default_touch_mode;
        }
        if let Ok(mut pid) = self.active_profile_id.lock() {
            *pid = profile.id.clone();
        }
        if let Ok(mut st) = self.session_stage.lock() {
            *st = SessionStage::Resolving;
        }

        // Update last_connected_epoch
        if let Ok(mut profiles) = self.profiles.lock() {
            if let Some(pc) = profiles.iter_mut().find(|p| p.id == profile.id) {
                pc.last_connected_epoch = Some(current_epoch_secs());
            }
            let _ = self.db.save_profiles(&profiles);
        }

        self.emit_state_snapshot();

        let session_config = RdpSessionConfig {
            profile_id: profile.id.clone(),
            friendly_name: profile.display_title(),
            hostname: profile.hostname.clone(),
            port: profile.port,
            username,
            password,
            domain,
            width,
            height,
            scale_factor: profile.scale_factor,
            enable_tls: profile.enable_tls,
            enable_nla: profile.enable_nla,
            clipboard_redirection: profile.clipboard_redirection,
            audio_mode: profile.audio_mode,
            temp_dir: self.db.thumbnails_dir().to_string_lossy().to_string(),
        };

        let controller_weak = Arc::downgrade(self);
        let handle = spawn_rdp_session(
            session_config,
            Arc::clone(&self.framebuffer),
            Arc::clone(&self.cert_store),
            Arc::new(move |worker_event| {
                if let Some(ctrl) = controller_weak.upgrade() {
                    ctrl.on_worker_event(worker_event);
                }
            }),
        );

        if let Ok(mut guard) = self.active_session.lock() {
            *guard = Some(handle);
        }

        Ok(())
    }

    fn handle_disconnect_session(&self) {
        let active_id = self
            .active_profile_id
            .lock()
            .map(|s| s.clone())
            .unwrap_or_default();

        if !active_id.is_empty() {
            let thumb_path = self.db.thumbnail_path_for(&active_id);
            let saved_ok = self
                .framebuffer
                .lock()
                .ok()
                .and_then(|fb| fb.save_thumbnail_png(&thumb_path, 320, 180).ok())
                .is_some();

            if saved_ok {
                if let Ok(mut profiles) = self.profiles.lock() {
                    if let Some(pc) = profiles.iter_mut().find(|p| p.id == active_id) {
                        pc.thumbnail_path =
                            Some(format!("file://{}", thumb_path.to_string_lossy()));
                    }
                    let _ = self.db.save_profiles(&profiles);
                }
            }
        }

        if let Ok(mut guard) = self.active_session.lock() {
            if let Some(handle) = guard.take() {
                handle.send_command(RdpCommand::Disconnect);
            }
        }
        if let Ok(mut pid) = self.active_profile_id.lock() {
            pid.clear();
        }
        if let Ok(mut st) = self.session_stage.lock() {
            *st = SessionStage::Disconnected;
        }
        self.emit_state_snapshot();
    }

    fn on_worker_event(&self, event: RdpWorkerEvent) {
        match event {
            RdpWorkerEvent::StageChanged {
                profile_id,
                stage,
                detail,
            } => {
                if let Ok(mut st) = self.session_stage.lock() {
                    *st = stage.clone();
                }
                self.emit_json(&json!({
                    "type": "session_stage",
                    "profileId": profile_id,
                    "stage": stage.as_str(),
                    "detail": detail,
                }));
            }
            RdpWorkerEvent::CertificatePrompt { profile_id, cert } => {
                self.emit_json(&json!({
                    "type": "certificate_prompt",
                    "profileId": profile_id,
                    "host": cert.host,
                    "port": cert.port,
                    "subjectCn": cert.subject_cn,
                    "issuerCn": cert.issuer_cn,
                    "validFrom": cert.valid_from,
                    "validUntil": cert.valid_until,
                    "sha256Fingerprint": cert.sha256_fingerprint,
                    "statusReason": cert.status_reason,
                    "isMismatchWarning": cert.is_mismatch_warning,
                }));
            }
            RdpWorkerEvent::DesktopResized { width, height } => {
                if let Ok(mut mapper) = self.input_mapper.lock() {
                    mapper.set_desktop_size(width, height);
                }
                self.emit_json(&json!({
                    "type": "desktop_resized",
                    "width": width,
                    "height": height,
                }));
            }
            RdpWorkerEvent::FrameUpdated { dirty, fps } => {
                let (cx, cy) = self
                    .framebuffer
                    .lock()
                    .map(|fb| fb.cursor_position())
                    .unwrap_or((0, 0));
                self.emit_json(&json!({
                    "type": "frame_updated",
                    "x": dirty.x,
                    "y": dirty.y,
                    "width": dirty.width,
                    "height": dirty.height,
                    "fps": fps,
                    "cursorX": cx,
                    "cursorY": cy,
                }));
            }
            RdpWorkerEvent::RemoteClipboardChanged { text } => {
                self.emit_json(&json!({
                    "type": "remote_clipboard",
                    "text": text,
                }));
            }
            RdpWorkerEvent::AudioChunk(chunk) => {
                let header = json!({
                    "type": "audio_pcm",
                    "sampleRate": chunk.sample_rate,
                    "channels": chunk.channels,
                    "bitsPerSample": chunk.bits_per_sample,
                });
                (self.ui_callback)(&header.to_string(), &chunk.pcm_bytes);
            }
            RdpWorkerEvent::SessionEnded {
                profile_id,
                reason,
                is_error,
            } => {
                if let Ok(mut st) = self.session_stage.lock() {
                    *st = if is_error {
                        SessionStage::Error
                    } else {
                        SessionStage::Disconnected
                    };
                }
                self.emit_json(&json!({
                    "type": "session_ended",
                    "profileId": profile_id,
                    "reason": reason,
                    "isError": is_error,
                }));
                self.emit_state_snapshot();
            }
        }
    }

    fn send_fastpath_events(
        &self,
        events: Vec<ironrdp_pdu::input::fast_path::FastPathInputEvent>,
    ) {
        if events.is_empty() {
            return;
        }
        if let Ok(guard) = self.active_session.lock() {
            if let Some(handle) = guard.as_ref() {
                handle.send_command(RdpCommand::FastPathInput(events.into()));
            }
        }
    }

    fn emit_json(&self, value: &Value) {
        (self.ui_callback)(&value.to_string(), &[]);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn update_preferences_are_exposed_and_other_setting_patches_preserve_them() {
        let dir = tempdir().unwrap();
        let db = StorageDatabase::open_at(
            dir.path().join("config"),
            dir.path().join("cache"),
        )
        .unwrap();
        let vault = CredentialVault::open_at(dir.path().join("vault")).unwrap();
        let events = Arc::new(Mutex::new(Vec::<Value>::new()));
        let captured = Arc::clone(&events);
        let ctrl = AppController::new(
            db.clone(),
            vault,
            Arc::new(move |json, _| {
                captured.lock().unwrap().push(serde_json::from_str(json).unwrap());
            }),
        );
        ctrl.dispatch_action(r#"{"action":"init"}"#).unwrap();
        let first = events.lock().unwrap()[0].clone();
        assert_eq!(first["appVersion"], env!("CARGO_PKG_VERSION"));
        assert_eq!(first["appFramework"], crate::storage::database::APP_FRAMEWORK);
        assert!(first["appArchitecture"].as_str().is_some());
        assert_eq!(first["settings"]["autoCheckUpdates"], true);
        ctrl.dispatch_action(r#"{"action":"save_settings","autoCheckUpdates":false,"skippedUpdateVersion":"0.1.4","lastUpdateCheckEpoch":1800000000}"#).unwrap();
        ctrl.dispatch_action(r#"{"action":"save_settings","themeMode":"light"}"#).unwrap();
        let stored = db.load_settings();
        assert!(!stored.auto_check_updates);
        assert_eq!(stored.skipped_update_version, "0.1.4");
        assert_eq!(stored.last_update_check_epoch, 1_800_000_000);
        assert_eq!(stored.theme_mode, "light");
        let last = events.lock().unwrap().last().cloned().unwrap();
        assert_eq!(last["settings"]["autoCheckUpdates"], false);
        assert_eq!(last["settings"]["skippedUpdateVersion"], "0.1.4");
        assert_eq!(last["settings"]["lastUpdateCheckEpoch"], 1_800_000_000_u64);
    }

    #[test]
    fn test_controller_pc_and_account_lifecycle() {
        let dir = tempdir().unwrap();
        let db = StorageDatabase::open_at(
            dir.path().join("config"),
            dir.path().join("cache"),
        )
        .unwrap();
        let vault = CredentialVault::open_at(dir.path().join("vault")).unwrap();
        let events = Arc::new(Mutex::new(Vec::<String>::new()));
        let events_clone = Arc::clone(&events);

        let ctrl = AppController::new(
            db,
            vault,
            Arc::new(move |json_str, _| {
                events_clone.lock().unwrap().push(json_str.to_string());
            }),
        );

        ctrl.dispatch_action(r#"{"action":"init"}"#).unwrap();
        ctrl.dispatch_action(
            r#"{
                "action":"save_pc",
                "hostInput":"10.10.0.50:3389",
                "friendlyName":"Studio Workstation",
                "resolutionPreset":"1920x1080",
                "scaleFactor":125
            }"#,
        )
        .unwrap();

        let last_event = events.lock().unwrap().last().cloned().unwrap();
        assert!(last_event.contains("Studio Workstation"));
        assert!(last_event.contains("Windows 11 Demo PC"));
    }

    #[test]
    fn test_demo_session_full_tofu_and_thumbnail_lifecycle() {
        let dir = tempdir().unwrap();
        let db = StorageDatabase::open_at(
            dir.path().join("config"),
            dir.path().join("cache"),
        )
        .unwrap();
        let vault = CredentialVault::open_at(dir.path().join("vault")).unwrap();
        let events = Arc::new(Mutex::new(Vec::<Value>::new()));
        let events_clone = Arc::clone(&events);

        let ctrl = AppController::new(
            db,
            vault,
            Arc::new(move |json_str, _| {
                if let Ok(val) = serde_json::from_str::<Value>(json_str) {
                    events_clone.lock().unwrap().push(val);
                }
            }),
        );

        ctrl.dispatch_action(r#"{"action":"init"}"#).unwrap();
        let demo_id = {
            let guard = events.lock().unwrap();
            let snap = guard.first().unwrap();
            snap["profiles"][0]["id"].as_str().unwrap().to_string()
        };

        ctrl.dispatch_action(&format!(
            r#"{{"action":"connect_pc","id":"{demo_id}","viewportWidth":1280,"viewportHeight":720}}"#
        ))
        .unwrap();

        // Wait for TOFU certificate_prompt
        let mut saw_cert_prompt = false;
        for _ in 0..40 {
            if events
                .lock()
                .unwrap()
                .iter()
                .any(|e| e["type"] == "certificate_prompt")
            {
                saw_cert_prompt = true;
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(25));
        }
        assert!(saw_cert_prompt, "Expected TOFU certificate_prompt event");

        // Trust Always
        ctrl.dispatch_action(r#"{"action":"respond_certificate","decision":"trust_always"}"#)
            .unwrap();

        // Wait for Connected stage
        let mut saw_connected = false;
        for _ in 0..40 {
            if events
                .lock()
                .unwrap()
                .iter()
                .any(|e| e["type"] == "session_stage" && e["stage"] == "connected")
            {
                saw_connected = true;
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(25));
        }
        assert!(saw_connected, "Expected session_stage connected");

        // Exercise trackpad move, click, sticky modifier, and resize
        ctrl.dispatch_action(r#"{"action":"trackpad_move","dx":24.5,"dy":-12.0}"#)
            .unwrap();
        ctrl.dispatch_action(r#"{"action":"mouse_click","button":1,"doubleClick":false}"#)
            .unwrap();
        ctrl.dispatch_action(r#"{"action":"toggle_modifier","modifier":"ctrl"}"#)
            .unwrap();
        ctrl.dispatch_action(r#"{"action":"send_virtual_key","key":"c"}"#)
            .unwrap();
        ctrl.dispatch_action(r#"{"action":"disconnect_session"}"#)
            .unwrap();

        // Verify thumbnail PNG was saved and attached to the profile
        let final_snap = events
            .lock()
            .unwrap()
            .iter()
            .rev()
            .find(|e| e["type"] == "state_snapshot")
            .cloned()
            .unwrap();
        let thumb_url = final_snap["profiles"][0]["thumbnailPath"]
            .as_str()
            .unwrap_or_default();
        assert!(
            thumb_url.starts_with("file://") && thumb_url.ends_with(".png"),
            "Expected saved PNG thumbnail path, got {thumb_url}"
        );
    }
}
