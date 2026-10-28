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

fn error_reporting_enabled() -> bool { true }

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppSettings {
    #[serde(default)]
    pub connection_defaults_revision: u32,
    pub theme_mode: String, // "dark", "light", "system"
    #[serde(default)]
    pub default_resolution: ResolutionMode,
    pub default_scale_factor: u32,
    #[serde(default)]
    pub default_touch_mode: TouchInputMode,
    pub default_audio_mode: AudioRedirectionMode,
    pub default_clipboard_enabled: bool,
    pub trackpad_speed_percent: u32,
    pub show_stats_overlay: bool,
    pub strict_cert_check: bool,
    #[serde(default = "error_reporting_enabled")]
    pub report_errors: bool,
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
            connection_defaults_revision: 1,
            theme_mode: "dark".to_string(),
            default_resolution: ResolutionMode::default(),
            default_scale_factor: 100,
            default_touch_mode: TouchInputMode::default(),
            default_audio_mode: AudioRedirectionMode::PlayOnDevice,
            default_clipboard_enabled: true,
            trackpad_speed_percent: 100,
            show_stats_overlay: false,
            strict_cert_check: false,
            report_errors: true,
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
        let mut settings: AppSettings = self.read_json_file("settings.json").unwrap_or_default();
        if settings.connection_defaults_revision < 1 {
            // Older releases persisted their implicit defaults on any settings
            // save. Upgrade those global defaults once, without editing saved PCs.
            if settings.default_resolution == ResolutionMode::Dynamic {
                settings.default_resolution = ResolutionMode::Native;
            }
            settings.default_touch_mode = TouchInputMode::DirectTouch;
            settings.connection_defaults_revision = 1;
            let _ = self.save_settings(&settings);
        }
        settings
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
    fn error_reporting_defaults_on_and_opt_out_survives_restart() {
        let dir = tempdir().unwrap();
        let db = StorageDatabase::open_at(dir.path().join("config"), dir.path().join("cache")).unwrap();
        let mut legacy = serde_json::to_value(AppSettings::default()).unwrap();
        legacy.as_object_mut().unwrap().remove("report_errors");
        legacy["theme_mode"] = serde_json::json!("light");
        let mut settings: AppSettings = serde_json::from_value(legacy).unwrap();
        assert!(settings.report_errors);
        assert_eq!(settings.theme_mode, "light");
        settings.report_errors = false;
        db.save_settings(&settings).unwrap();
        let reopened = StorageDatabase::open_at(dir.path().join("config"), dir.path().join("cache")).unwrap();
        assert!(!reopened.load_settings().report_errors);
    }

    #[test]
    fn legacy_global_defaults_migrate_once_without_changing_saved_pcs() {
        let dir = tempdir().unwrap();
        let config = dir.path().join("config");
        let cache = dir.path().join("cache");
        let db = StorageDatabase::open_at(config.clone(), cache.clone()).unwrap();
        let mut legacy = serde_json::to_value(AppSettings::default()).unwrap();
        legacy.as_object_mut().unwrap().remove("connection_defaults_revision");
        legacy["default_resolution"] = serde_json::json!({"mode":"dynamic"});
        legacy["default_touch_mode"] = serde_json::json!("mouse_pointer");
        legacy["report_errors"] = serde_json::json!(false);
        legacy["theme_mode"] = serde_json::json!("light");
        db.write_json_atomic("settings.json", &legacy).unwrap();
        let mut pc = PcProfile::new("host-01", "").unwrap();
        pc.resolution_mode = ResolutionMode::Dynamic;
        pc.default_touch_mode = TouchInputMode::MousePointer;
        db.save_profiles(&[pc.clone()]).unwrap();
        let mut migrated = db.load_settings();
        assert_eq!(migrated.default_resolution, ResolutionMode::Native);
        assert_eq!(migrated.default_touch_mode, TouchInputMode::DirectTouch);
        assert_eq!(migrated.theme_mode, "light");
        assert!(!migrated.report_errors);
        assert_eq!(db.load_profiles(), vec![pc]);
        // Later explicit global choices must survive subsequent restarts.
        migrated.default_resolution = ResolutionMode::Dynamic;
        migrated.default_touch_mode = TouchInputMode::MousePointer;
        db.save_settings(&migrated).unwrap();
        let reopened = StorageDatabase::open_at(config, cache).unwrap();
        assert_eq!(reopened.load_settings(), migrated);
    }

    #[test]
    fn native_resolution_defaults_preserve_saved_dynamic_choices() {
        let dir = tempdir().unwrap();
        let db = StorageDatabase::open_at(dir.path().join("config"), dir.path().join("cache")).unwrap();
        assert_eq!(db.load_settings().default_resolution, ResolutionMode::Native);
        let profile = PcProfile::new("host-01", "").unwrap();
        assert_eq!(profile.resolution_mode, ResolutionMode::Native);
        let mut legacy = serde_json::to_value(AppSettings::default()).unwrap();
        legacy.as_object_mut().unwrap().remove("default_resolution");
        let mut settings: AppSettings = serde_json::from_value(legacy).unwrap();
        assert_eq!(settings.default_resolution, ResolutionMode::Native);
        settings.default_resolution = ResolutionMode::Dynamic;
        db.save_settings(&settings).unwrap();
        assert_eq!(db.load_settings().default_resolution, ResolutionMode::Dynamic);
        let mut profile = profile;
        profile.resolution_mode = ResolutionMode::Dynamic;
        profile.default_touch_mode = TouchInputMode::MousePointer;
        db.save_profiles(&[profile.clone()]).unwrap();
        assert_eq!(db.load_profiles(), vec![profile]);
    }

    #[test]
    fn touch_defaults_preserve_saved_trackpad_choices() {
        assert_eq!(AppSettings::default().default_touch_mode, TouchInputMode::DirectTouch);
        let mut settings = serde_json::to_value(AppSettings::default()).unwrap();
        settings.as_object_mut().unwrap().remove("default_touch_mode");
        assert_eq!(serde_json::from_value::<AppSettings>(settings.clone()).unwrap().default_touch_mode, TouchInputMode::DirectTouch);
        settings["default_touch_mode"] = serde_json::json!("mouse_pointer");
        assert_eq!(serde_json::from_value::<AppSettings>(settings).unwrap().default_touch_mode, TouchInputMode::MousePointer);
        let profile = PcProfile::new("host-01", "").unwrap();
        assert_eq!(profile.default_touch_mode, TouchInputMode::DirectTouch);
        let mut saved = serde_json::to_value(profile).unwrap();
        saved["default_touch_mode"] = serde_json::json!("mouse_pointer");
        assert_eq!(serde_json::from_value::<PcProfile>(saved).unwrap().default_touch_mode, TouchInputMode::MousePointer);
    }

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
