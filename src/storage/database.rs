use std::fs;
use std::path::{Path, PathBuf};

use serde::{de::DeserializeOwned, Deserialize, Serialize};

use crate::models::{
    AudioRedirectionMode, CertStore, PcProfile, ResolutionMode, TouchInputMode, UserAccount,
};

pub const APP_ID: &str = "rdp-client-ut.zzvvmm";
pub const APP_FRAMEWORK: &str = "ubuntu-touch-24.04-1.x";

fn automatic_updates_enabled() -> bool {
    true
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppSettings {
    pub theme_mode: String, // "dark", "light", "system"
    pub default_resolution: ResolutionMode,
    pub default_scale_factor: u32,
    pub default_touch_mode: TouchInputMode,
    pub default_audio_mode: AudioRedirectionMode,
    pub default_clipboard_enabled: bool,
    pub trackpad_speed_percent: u32,
    pub show_stats_overlay: bool,
    pub strict_cert_check: bool,
    #[serde(default = "automatic_updates_enabled")]
    pub auto_check_updates: bool,
    #[serde(default)]
    pub skipped_update_version: String,
    #[serde(default)]
    pub last_update_check_epoch: u64,
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            theme_mode: "dark".to_string(),
            default_resolution: ResolutionMode::Dynamic,
            default_scale_factor: 100,
            default_touch_mode: TouchInputMode::MousePointer,
            default_audio_mode: AudioRedirectionMode::PlayOnDevice,
            default_clipboard_enabled: true,
            trackpad_speed_percent: 100,
            show_stats_overlay: false,
            strict_cert_check: false,
            auto_check_updates: true,
            skipped_update_version: String::new(),
            last_update_check_epoch: 0,
        }
    }
}

#[derive(Debug, Clone)]
pub struct StorageDatabase {
    config_dir: PathBuf,
    cache_dir: PathBuf,
}

impl StorageDatabase {
    pub fn open_default() -> Result<Self, String> {
        let base_config = std::env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .or_else(dirs::config_dir)
            .unwrap_or_else(|| PathBuf::from("/tmp"));
        let base_cache = std::env::var_os("XDG_CACHE_HOME")
            .map(PathBuf::from)
            .or_else(dirs::cache_dir)
            .unwrap_or_else(|| PathBuf::from("/tmp"));

        Self::open_at(base_config.join(APP_ID), base_cache.join(APP_ID))
    }

    pub fn open_at(config_dir: PathBuf, cache_dir: PathBuf) -> Result<Self, String> {
        fs::create_dir_all(&config_dir)
            .map_err(|e| format!("Failed to create config dir {:?}: {e}", config_dir))?;
        fs::create_dir_all(cache_dir.join("thumbnails"))
            .map_err(|e| format!("Failed to create thumbnails dir {:?}: {e}", cache_dir))?;

        Ok(Self {
            config_dir,
            cache_dir,
        })
    }

    pub fn config_dir(&self) -> &Path {
        &self.config_dir
    }

    pub fn thumbnails_dir(&self) -> PathBuf {
        self.cache_dir.join("thumbnails")
    }

    pub fn thumbnail_path_for(&self, profile_id: &str) -> PathBuf {
        let safe_id: String = profile_id
            .chars()
            .filter(|c| c.is_ascii_alphanumeric() || *c == '-')
            .collect();
        self.thumbnails_dir().join(format!("{safe_id}.png"))
    }

    pub fn load_profiles(&self) -> Vec<PcProfile> {
        self.read_json_file("profiles.json").unwrap_or_default()
    }

    pub fn save_profiles(&self, profiles: &[PcProfile]) -> Result<(), String> {
        self.write_json_atomic("profiles.json", &profiles)
    }

    pub fn load_accounts(&self) -> Vec<UserAccount> {
        self.read_json_file("accounts.json").unwrap_or_default()
    }

    pub fn save_accounts(&self, accounts: &[UserAccount]) -> Result<(), String> {
        self.write_json_atomic("accounts.json", &accounts)
    }

    pub fn load_cert_store(&self) -> CertStore {
        self.read_json_file("known_hosts.json").unwrap_or_default()
    }

    pub fn save_cert_store(&self, store: &CertStore) -> Result<(), String> {
        self.write_json_atomic("known_hosts.json", store)
    }

    pub fn load_settings(&self) -> AppSettings {
        self.read_json_file("settings.json").unwrap_or_default()
    }

    pub fn save_settings(&self, settings: &AppSettings) -> Result<(), String> {
        self.write_json_atomic("settings.json", settings)
    }

    fn read_json_file<T: DeserializeOwned>(&self, filename: &str) -> Option<T> {
        let path = self.config_dir.join(filename);
        let content = fs::read_to_string(path).ok()?;
        serde_json::from_str(&content).ok()
    }

    fn write_json_atomic<T: Serialize>(&self, filename: &str, value: &T) -> Result<(), String> {
        let target = self.config_dir.join(filename);
        let tmp = self.config_dir.join(format!(".{filename}.tmp"));
        let serialized = serde_json::to_string_pretty(value)
            .map_err(|e| format!("Failed to serialize {filename}: {e}"))?;
        fs::write(&tmp, serialized)
            .map_err(|e| format!("Failed to write temporary file {:?}: {e}", tmp))?;
        fs::rename(&tmp, &target)
            .map_err(|e| format!("Failed to commit file {:?}: {e}", target))?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn legacy_settings_keep_preferences_and_enable_update_checks() {
        let mut legacy = serde_json::to_value(AppSettings::default()).unwrap();
        let object = legacy.as_object_mut().unwrap();
        object.remove("auto_check_updates");
        object.remove("skipped_update_version");
        object.remove("last_update_check_epoch");
        object.insert("theme_mode".into(), serde_json::json!("light"));
        object.insert("trackpad_speed_percent".into(), serde_json::json!(150));
        let settings: AppSettings = serde_json::from_value(legacy).unwrap();
        assert!(settings.auto_check_updates);
        assert!(settings.skipped_update_version.is_empty());
        assert_eq!(settings.last_update_check_epoch, 0);
        assert_eq!(settings.theme_mode, "light");
        assert_eq!(settings.trackpad_speed_percent, 150);
    }

    #[test]
    fn update_preferences_survive_reopening_storage() {
        let dir = tempdir().unwrap();
        let config = dir.path().join("config");
        let cache = dir.path().join("cache");
        let db = StorageDatabase::open_at(config.clone(), cache.clone()).unwrap();
        let settings = AppSettings {
            auto_check_updates: false,
            skipped_update_version: "0.1.4".into(),
            last_update_check_epoch: 1_800_000_000,
            ..AppSettings::default()
        };
        db.save_settings(&settings).unwrap();
        let reopened = StorageDatabase::open_at(config, cache).unwrap();
        assert_eq!(reopened.load_settings(), settings);
    }

    #[test]
    fn test_storage_crud_roundtrip() {
        let dir = tempdir().unwrap();
        let db = StorageDatabase::open_at(
            dir.path().join("config"),
            dir.path().join("cache"),
        )
        .unwrap();

        let pc = PcProfile::new("192.168.1.42:3389", "Home Gaming PC").unwrap();
        db.save_profiles(std::slice::from_ref(&pc)).unwrap();
        let loaded = db.load_profiles();
        assert_eq!(loaded.len(), 1);
        assert_eq!(loaded[0].friendly_name, "Home Gaming PC");

        let acct = UserAccount::new("WORK\\admin", "", "Work Admin").unwrap();
        db.save_accounts(std::slice::from_ref(&acct)).unwrap();
        assert_eq!(db.load_accounts().len(), 1);
    }
}
