//! Build-time identity: both frontends target Linux, so the OS is insufficient.

#[cfg(feature = "ubuntu-touch")]
pub const APP_ID: &str = "rdp-client-ut.zzvvmm";
#[cfg(not(feature = "ubuntu-touch"))]
pub const APP_ID: &str = "open-rdp-client";
#[cfg(feature = "ubuntu-touch")]
pub const APP_FRAMEWORK: &str = "ubuntu-touch-24.04-1.x";
#[cfg(not(feature = "ubuntu-touch"))]
pub const APP_FRAMEWORK: &str = "";
#[cfg(feature = "ubuntu-touch")]
pub const PLATFORM: &str = "ubuntu-touch";
#[cfg(not(feature = "ubuntu-touch"))]
pub const PLATFORM: &str = "linux";
#[cfg(feature = "ubuntu-touch")]
pub const UPDATE_PROVIDER: &str = "openstore";
#[cfg(not(feature = "ubuntu-touch"))]
pub const UPDATE_PROVIDER: &str = "manual";
#[cfg(feature = "ubuntu-touch")]
pub const RDP_CLIENT_NAME: &str = "UbuntuTouch-RDP";
#[cfg(not(feature = "ubuntu-touch"))]
pub const RDP_CLIENT_NAME: &str = "OpenRDP-Linux";

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn platform_identity_keeps_storage_and_updates_separate() {
        if cfg!(feature = "ubuntu-touch") {
            assert_eq!(APP_ID, "rdp-client-ut.zzvvmm");
            assert_eq!(APP_FRAMEWORK, "ubuntu-touch-24.04-1.x");
            assert_eq!(UPDATE_PROVIDER, "openstore");
        } else {
            assert_eq!(APP_ID, "open-rdp-client");
            assert_ne!(APP_ID, "rdp-client-ut.zzvvmm");
            assert!(APP_FRAMEWORK.is_empty());
            assert_eq!(UPDATE_PROVIDER, "manual");
        }
    }
}
