use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;

use base64::Engine as _;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::storage::database::APP_ID;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct VaultFile {
    entries: BTreeMap<String, String>,
}

#[derive(Debug, Clone)]
pub struct CredentialVault {
    vault_dir: PathBuf,
    master_key: [u8; 32],
}

impl CredentialVault {
    pub fn open_default() -> Result<Self, String> {
        let base_data = std::env::var_os("XDG_DATA_HOME")
            .map(PathBuf::from)
            .or_else(dirs::data_local_dir)
            .unwrap_or_else(|| PathBuf::from("/tmp"));
        Self::open_at(base_data.join(APP_ID))
    }

    pub fn open_at(vault_dir: PathBuf) -> Result<Self, String> {
        fs::create_dir_all(&vault_dir)
            .map_err(|e| format!("Failed to create credential vault dir {:?}: {e}", vault_dir))?;

        let key_path = vault_dir.join(".vault.key");
        let master_key = if let Ok(bytes) = fs::read(&key_path) {
            if bytes.len() == 32 {
                let mut arr = [0u8; 32];
                arr.copy_from_slice(&bytes);
                arr
            } else {
                Self::generate_and_save_key(&key_path)?
            }
        } else {
            Self::generate_and_save_key(&key_path)?
        };

        Ok(Self {
            vault_dir,
            master_key,
        })
    }

    fn generate_and_save_key(key_path: &PathBuf) -> Result<[u8; 32], String> {
        let seed = format!(
            "{}-{:?}",
            uuid::Uuid::new_v4(),
            std::time::SystemTime::now()
        );
        let digest = Sha256::digest(seed.as_bytes());
        let mut key = [0u8; 32];
        key.copy_from_slice(&digest);
        fs::write(key_path, key).map_err(|e| format!("Failed to write vault key: {e}"))?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(key_path, fs::Permissions::from_mode(0o600));
        }
        Ok(key)
    }

    pub fn set_password(&self, account_id: &str, password: &str) -> Result<(), String> {
        let mut vault = self.read_vault();
        if password.is_empty() {
            vault.entries.remove(account_id);
        } else {
            let encrypted = self.seal(account_id, password.as_bytes());
            vault.entries.insert(account_id.to_string(), encrypted);
        }
        self.write_vault(&vault)
    }

    pub fn get_password(&self, account_id: &str) -> Option<String> {
        let vault = self.read_vault();
        let encoded = vault.entries.get(account_id)?;
        let bytes = self.open_sealed(account_id, encoded)?;
        String::from_utf8(bytes).ok()
    }

    pub fn delete_password(&self, account_id: &str) -> Result<(), String> {
        let mut vault = self.read_vault();
        vault.entries.remove(account_id);
        self.write_vault(&vault)
    }

    fn seal(&self, context_id: &str, plaintext: &[u8]) -> String {
        let nonce = uuid::Uuid::new_v4().into_bytes();
        let keystream = Self::derive_stream(&self.master_key, context_id, &nonce, plaintext.len());
        let ciphertext: Vec<u8> = plaintext
            .iter()
            .zip(keystream.iter())
            .map(|(p, k)| p ^ k)
            .collect();

        let tag = Self::compute_tag(&self.master_key, context_id, &nonce, &ciphertext);
        let mut payload = Vec::with_capacity(16 + 32 + ciphertext.len());
        payload.extend_from_slice(&nonce);
        payload.extend_from_slice(&tag);
        payload.extend_from_slice(&ciphertext);
        base64::engine::general_purpose::STANDARD.encode(payload)
    }

    fn open_sealed(&self, context_id: &str, encoded: &str) -> Option<Vec<u8>> {
        let payload = base64::engine::general_purpose::STANDARD.decode(encoded).ok()?;
        if payload.len() < 48 {
            return None;
        }
        let nonce = &payload[0..16];
        let tag = &payload[16..48];
        let ciphertext = &payload[48..];

        let expected_tag = Self::compute_tag(&self.master_key, context_id, nonce, ciphertext);
        if tag != expected_tag.as_slice() {
            return None;
        }
        let keystream = Self::derive_stream(&self.master_key, context_id, nonce, ciphertext.len());
        Some(
            ciphertext
                .iter()
                .zip(keystream.iter())
                .map(|(c, k)| c ^ k)
                .collect(),
        )
    }

    fn derive_stream(master_key: &[u8; 32], context_id: &str, nonce: &[u8], len: usize) -> Vec<u8> {
        let mut out = Vec::with_capacity(len);
        let mut counter = 0u32;
        while out.len() < len {
            let mut hasher = Sha256::new();
            hasher.update(master_key);
            hasher.update(context_id.as_bytes());
            hasher.update(nonce);
            hasher.update(counter.to_le_bytes());
            let block = hasher.finalize();
            let remaining = len - out.len();
            out.extend_from_slice(&block[..remaining.min(32)]);
            counter = counter.wrapping_add(1);
        }
        out
    }

    fn compute_tag(
        master_key: &[u8; 32],
        context_id: &str,
        nonce: &[u8],
        ciphertext: &[u8],
    ) -> [u8; 32] {
        let mut hasher = Sha256::new();
        hasher.update(b"RDP-UT-VAULT-MAC-V1");
        hasher.update(master_key);
        hasher.update(context_id.as_bytes());
        hasher.update(nonce);
        hasher.update(ciphertext);
        let digest = hasher.finalize();
        let mut out = [0u8; 32];
        out.copy_from_slice(&digest);
        out
    }

    fn read_vault(&self) -> VaultFile {
        let path = self.vault_dir.join("vault.json");
        fs::read_to_string(path)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default()
    }

    fn write_vault(&self, vault: &VaultFile) -> Result<(), String> {
        let path = self.vault_dir.join("vault.json");
        let tmp = self.vault_dir.join(".vault.json.tmp");
        let data = serde_json::to_string_pretty(vault)
            .map_err(|e| format!("Failed to serialize vault: {e}"))?;
        fs::write(&tmp, data).map_err(|e| format!("Failed to write vault: {e}"))?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&tmp, fs::Permissions::from_mode(0o600));
        }
        fs::rename(&tmp, &path).map_err(|e| format!("Failed to commit vault: {e}"))?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_credential_vault_encrypt_decrypt() {
        let dir = tempdir().unwrap();
        let vault = CredentialVault::open_at(dir.path().to_path_buf()).unwrap();
        vault.set_password("acct-1", "S3cr3t!Pass#2026").unwrap();

        assert_eq!(
            vault.get_password("acct-1").as_deref(),
            Some("S3cr3t!Pass#2026")
        );
        assert_eq!(vault.get_password("acct-2"), None);

        vault.delete_password("acct-1").unwrap();
        assert_eq!(vault.get_password("acct-1"), None);
    }
}
