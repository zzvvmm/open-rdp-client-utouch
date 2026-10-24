use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use x509_cert::der::Encode;

use crate::models::account::current_epoch_secs;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CertTrustDecision {
    TrustAlways,
    TrustOnce,
    Reject,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CertificateInfo {
    pub host: String,
    pub port: u16,
    pub subject_cn: String,
    pub issuer_cn: String,
    pub valid_from: String,
    pub valid_until: String,
    pub sha256_fingerprint: String,
    pub status_reason: String,
    pub is_mismatch_warning: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KnownHostCert {
    pub host_port: String,
    pub subject_cn: String,
    pub issuer_cn: String,
    pub valid_from: String,
    pub valid_until: String,
    pub sha256_fingerprint: String,
    pub trusted_at_epoch: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CertVerificationOutcome {
    Trusted,
    UnknownHost(CertificateInfo),
    FingerprintMismatch {
        expected: String,
        actual: CertificateInfo,
    },
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CertStore {
    pub known_hosts: BTreeMap<String, KnownHostCert>,
    #[serde(skip)]
    pub session_trusted: BTreeMap<String, String>,
}

impl CertStore {
    pub fn host_key(host: &str, port: u16) -> String {
        format!("{}:{port}", host.trim().to_ascii_lowercase())
    }

    pub fn verify(&self, cert: &CertificateInfo) -> CertVerificationOutcome {
        let key = Self::host_key(&cert.host, cert.port);
        if let Some(fp) = self.session_trusted.get(&key) {
            if fp.eq_ignore_ascii_case(&cert.sha256_fingerprint) {
                return CertVerificationOutcome::Trusted;
            }
        }
        if let Some(saved) = self.known_hosts.get(&key) {
            if saved
                .sha256_fingerprint
                .eq_ignore_ascii_case(&cert.sha256_fingerprint)
            {
                CertVerificationOutcome::Trusted
            } else {
                let mut warning_cert = cert.clone();
                warning_cert.is_mismatch_warning = true;
                warning_cert.status_reason = format!(
                    "Certificate fingerprint changed! Previously trusted: {}",
                    saved.sha256_fingerprint
                );
                CertVerificationOutcome::FingerprintMismatch {
                    expected: saved.sha256_fingerprint.clone(),
                    actual: warning_cert,
                }
            }
        } else {
            let mut prompt_cert = cert.clone();
            prompt_cert.is_mismatch_warning = false;
            prompt_cert.status_reason =
                "First connection to this PC (Trust-On-First-Use)".to_string();
            CertVerificationOutcome::UnknownHost(prompt_cert)
        }
    }

    pub fn record_decision(&mut self, cert: &CertificateInfo, decision: CertTrustDecision) {
        let key = Self::host_key(&cert.host, cert.port);
        match decision {
            CertTrustDecision::TrustAlways => {
                self.session_trusted
                    .insert(key.clone(), cert.sha256_fingerprint.clone());
                self.known_hosts.insert(
                    key.clone(),
                    KnownHostCert {
                        host_port: key,
                        subject_cn: cert.subject_cn.clone(),
                        issuer_cn: cert.issuer_cn.clone(),
                        valid_from: cert.valid_from.clone(),
                        valid_until: cert.valid_until.clone(),
                        sha256_fingerprint: cert.sha256_fingerprint.clone(),
                        trusted_at_epoch: current_epoch_secs(),
                    },
                );
            }
            CertTrustDecision::TrustOnce => {
                self.session_trusted
                    .insert(key, cert.sha256_fingerprint.clone());
            }
            CertTrustDecision::Reject => {}
        }
    }

    pub fn remove_host(&mut self, host_port: &str) -> bool {
        let normalized = host_port.trim().to_ascii_lowercase();
        self.session_trusted.remove(&normalized);
        self.known_hosts.remove(&normalized).is_some()
    }

    pub fn list_known_hosts(&self) -> Vec<KnownHostCert> {
        self.known_hosts.values().cloned().collect()
    }
}

pub fn format_sha256_fingerprint(der_bytes: &[u8]) -> String {
    let digest = Sha256::digest(der_bytes);
    digest
        .iter()
        .map(|b| format!("{b:02X}"))
        .collect::<Vec<_>>()
        .join(":")
}

pub fn inspect_x509_certificate(
    host: &str,
    port: u16,
    cert: &x509_cert::Certificate,
) -> Result<CertificateInfo, String> {
    let der = cert
        .to_der()
        .map_err(|e| format!("Failed to encode X509 DER: {e}"))?;
    let sha256_fingerprint = format_sha256_fingerprint(&der);
    let subject_cn = cert.tbs_certificate.subject.to_string();
    let issuer_cn = cert.tbs_certificate.issuer.to_string();
    let valid_from = cert
        .tbs_certificate
        .validity
        .not_before
        .to_date_time()
        .to_string();
    let valid_until = cert
        .tbs_certificate
        .validity
        .not_after
        .to_date_time()
        .to_string();

    Ok(CertificateInfo {
        host: host.to_string(),
        port,
        subject_cn: if subject_cn.is_empty() {
            host.to_string()
        } else {
            subject_cn
        },
        issuer_cn: if issuer_cn.is_empty() {
            "Self-Signed RDP Server".to_string()
        } else {
            issuer_cn
        },
        valid_from,
        valid_until,
        sha256_fingerprint,
        status_reason: "Untrusted certificate".to_string(),
        is_mismatch_warning: false,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cert_store_tofu_and_mismatch() {
        let mut store = CertStore::default();
        let cert1 = CertificateInfo {
            host: "10.0.0.25".to_string(),
            port: 3389,
            subject_cn: "CN=WIN11-PRO".to_string(),
            issuer_cn: "CN=WIN11-PRO".to_string(),
            valid_from: "2026-01-01".to_string(),
            valid_until: "2027-01-01".to_string(),
            sha256_fingerprint: "AA:BB:CC:DD".to_string(),
            status_reason: String::new(),
            is_mismatch_warning: false,
        };

        assert!(matches!(
            store.verify(&cert1),
            CertVerificationOutcome::UnknownHost(_)
        ));

        store.record_decision(&cert1, CertTrustDecision::TrustAlways);
        assert_eq!(store.verify(&cert1), CertVerificationOutcome::Trusted);

        let mut cert2 = cert1.clone();
        cert2.sha256_fingerprint = "11:22:33:44".to_string();
        assert!(matches!(
            store.verify(&cert2),
            CertVerificationOutcome::FingerprintMismatch { .. }
        ));
    }
}
