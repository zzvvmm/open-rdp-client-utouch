use std::process::Command;

#[test]
fn default_storage_uses_the_selected_platform_and_preserves_other_platform_data() {
    let dir = tempfile::tempdir().unwrap();
    let config = dir.path().join("config");
    let data = dir.path().join("data");
    let cache = dir.path().join("cache");
    let other_id = if cfg!(feature = "ubuntu-touch") {
        "open-rdp-client"
    } else {
        "rdp-client-ut.zzvvmm"
    };
    let other_data = data.join(other_id);
    std::fs::create_dir_all(&other_data).unwrap();
    std::fs::write(other_data.join("sentinel"), "existing user data").unwrap();
    let output = Command::new(env!("CARGO_BIN_EXE_rdp-client-ut-cli"))
        .arg("--self-test")
        .env("XDG_CONFIG_HOME", &config)
        .env("XDG_DATA_HOME", &data)
        .env("XDG_CACHE_HOME", &cache)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let id = rdp_client_ut::platform::APP_ID;
    assert!(config.join(id).join("profiles.json").is_file());
    assert!(data.join(id).join(".vault.key").is_file());
    assert!(cache.join(id).is_dir());
    assert_eq!(
        std::fs::read_to_string(other_data.join("sentinel")).unwrap(),
        "existing user data"
    );
    assert!(!config.join(other_id).exists());
    let snapshot: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(snapshot["appPlatform"], rdp_client_ut::platform::PLATFORM);
    assert_eq!(
        snapshot["updateProvider"],
        rdp_client_ut::platform::UPDATE_PROVIDER
    );
}
