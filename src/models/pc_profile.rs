use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "mode", rename_all = "snake_case")]
pub enum ResolutionMode {
    Dynamic,
    Native,
    Fixed { width: u16, height: u16 },
}

impl Default for ResolutionMode {
    fn default() -> Self {
        Self::Dynamic
    }
}

impl ResolutionMode {
    pub fn from_preset_key(key: &str) -> Self {
        match key.trim() {
            "native" => Self::Native,
            "1920x1080" => Self::Fixed {
                width: 1920,
                height: 1080,
            },
            "1600x900" => Self::Fixed {
                width: 1600,
                height: 900,
            },
            "1366x768" => Self::Fixed {
                width: 1366,
                height: 768,
            },
            "1280x720" => Self::Fixed {
                width: 1280,
                height: 720,
            },
            _ => Self::Dynamic,
        }
    }

    pub fn preset_key(&self) -> String {
        match self {
            Self::Dynamic => "dynamic".to_string(),
            Self::Native => "native".to_string(),
            Self::Fixed { width, height } => format!("{width}x{height}"),
        }
    }

    pub fn display_label(&self) -> String {
        match self {
            Self::Dynamic => "Dynamic (Fit window)".to_string(),
            Self::Native => "Match device screen".to_string(),
            Self::Fixed { width, height } => format!("{width} × {height}"),
        }
    }

    pub fn resolve_dimensions(&self, viewport_w: u16, viewport_h: u16) -> (u16, u16) {
        let clamp_even = |val: u16, fallback: u16| -> u16 {
            let v = if val < 640 { fallback } else { val.min(4096) };
            v & !1
        };
        match self {
            Self::Dynamic | Self::Native => (
                clamp_even(viewport_w, 1280),
                clamp_even(viewport_h, 720),
            ),
            Self::Fixed { width, height } => (
                clamp_even(*width, 1280),
                clamp_even(*height, 720),
            ),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AudioRedirectionMode {
    PlayOnDevice,
    PlayOnRemote,
    Disabled,
}

impl Default for AudioRedirectionMode {
    fn default() -> Self {
        Self::PlayOnDevice
    }
}

impl AudioRedirectionMode {
    pub fn from_key(key: &str) -> Self {
        match key {
            "remote" | "play_on_remote" => Self::PlayOnRemote,
            "disabled" | "none" => Self::Disabled,
            _ => Self::PlayOnDevice,
        }
    }

    pub fn as_key(&self) -> &'static str {
        match self {
            Self::PlayOnDevice => "play_on_device",
            Self::PlayOnRemote => "play_on_remote",
            Self::Disabled => "disabled",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TouchInputMode {
    MousePointer,
    DirectTouch,
}

impl Default for TouchInputMode {
    fn default() -> Self {
        Self::DirectTouch
    }
}

impl TouchInputMode {
    pub fn from_key(key: &str) -> Self {
        match key {
            "direct" | "direct_touch" => Self::DirectTouch,
            "mouse_pointer" => Self::MousePointer,
            _ => Self::default(),
        }
    }

    pub fn as_key(&self) -> &'static str {
        match self {
            Self::MousePointer => "mouse_pointer",
            Self::DirectTouch => "direct_touch",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PcProfile {
    pub id: String,
    pub hostname: String,
    pub port: u16,
    pub friendly_name: String,
    pub account_id: Option<String>,
    pub resolution_mode: ResolutionMode,
    pub scale_factor: u32,
    pub clipboard_redirection: bool,
    pub audio_mode: AudioRedirectionMode,
    #[serde(default)]
    pub default_touch_mode: TouchInputMode,
    pub enable_nla: bool,
    pub enable_tls: bool,
    pub group_name: String,
    pub last_connected_epoch: Option<u64>,
    pub thumbnail_path: Option<String>,
    pub favorite: bool,
}

impl PcProfile {
    pub fn new(host_input: &str, friendly_name: &str) -> Result<Self, String> {
        let (hostname, port) = parse_host_port(host_input)?;
        Ok(Self {
            id: Uuid::new_v4().to_string(),
            hostname,
            port,
            friendly_name: friendly_name.trim().to_string(),
            account_id: None,
            resolution_mode: ResolutionMode::Dynamic,
            scale_factor: 100,
            clipboard_redirection: true,
            audio_mode: AudioRedirectionMode::PlayOnDevice,
            default_touch_mode: TouchInputMode::default(),
            enable_nla: true,
            enable_tls: true,
            group_name: "Saved PCs".to_string(),
            last_connected_epoch: None,
            thumbnail_path: None,
            favorite: false,
        })
    }

    pub fn display_title(&self) -> String {
        if self.friendly_name.trim().is_empty() {
            self.address_string()
        } else {
            self.friendly_name.clone()
        }
    }

    pub fn address_string(&self) -> String {
        if self.port == 3389 {
            self.hostname.clone()
        } else if self.hostname.contains(':') {
            format!("[{}]:{}", self.hostname, self.port)
        } else {
            format!("{}:{}", self.hostname, self.port)
        }
    }

    pub fn socket_destination(&self) -> String {
        if self.hostname.contains(':') {
            format!("[{}]:{}", self.hostname, self.port)
        } else {
            format!("{}:{}", self.hostname, self.port)
        }
    }
}

/// Parses an RDP host or `host:port` string (including IPv6 `[::1]:3389`) into `(hostname, port)`.
pub fn parse_host_port(input: &str) -> Result<(String, u16), String> {
    let trimmed = input.trim();
    if trimmed.is_empty() {
        return Err("PC hostname or IP address cannot be empty".to_string());
    }

    if let Some(rest) = trimmed.strip_prefix('[') {
        let (host, after_bracket) = rest
            .split_once(']')
            .ok_or_else(|| "Invalid IPv6 bracket syntax".to_string())?;
        if host.is_empty() {
            return Err("IPv6 address cannot be empty".to_string());
        }
        let port = if let Some(port_str) = after_bracket.strip_prefix(':') {
            port_str
                .parse::<u16>()
                .ok()
                .filter(|&p| p > 0)
                .ok_or_else(|| format!("Invalid RDP port '{port_str}'"))?
        } else if after_bracket.is_empty() {
            3389
        } else {
            return Err("Unexpected characters after IPv6 address".to_string());
        };
        return Ok((host.to_string(), port));
    }

    // Count colons: if more than 1 colon without brackets, treat as bare IPv6 with default port 3389
    let colon_count = trimmed.chars().filter(|&c| c == ':').count();
    if colon_count > 1 {
        return Ok((trimmed.to_string(), 3389));
    }

    if let Some((host, port_str)) = trimmed.rsplit_once(':') {
        let host = host.trim();
        if host.is_empty() {
            return Err("PC hostname cannot be empty".to_string());
        }
        let port = port_str
            .trim()
            .parse::<u16>()
            .ok()
            .filter(|&p| p > 0)
            .ok_or_else(|| format!("Invalid RDP port '{port_str}'"))?;
        Ok((host.to_string(), port))
    } else {
        Ok((trimmed.to_string(), 3389))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_host_port_variants() {
        assert_eq!(
            parse_host_port("192.168.1.100").unwrap(),
            ("192.168.1.100".to_string(), 3389)
        );
        assert_eq!(
            parse_host_port("work-pc.local:3390").unwrap(),
            ("work-pc.local".to_string(), 3390)
        );
        assert_eq!(
            parse_host_port("[fe80::1]:3391").unwrap(),
            ("fe80::1".to_string(), 3391)
        );
        assert_eq!(
            parse_host_port("2001:db8::1").unwrap(),
            ("2001:db8::1".to_string(), 3389)
        );
        assert!(parse_host_port("").is_err());
        assert!(parse_host_port("host:0").is_err());
        assert!(parse_host_port("host:99999").is_err());
    }

    #[test]
    fn test_resolution_mode_even_clamping() {
        let mode = ResolutionMode::Dynamic;
        assert_eq!(mode.resolve_dimensions(1081, 2399), (1080, 2398));
        assert_eq!(mode.resolve_dimensions(200, 200), (1280, 720));
    }
}
