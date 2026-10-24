use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserAccount {
    pub id: String,
    pub display_name: String,
    pub username: String,
    pub domain: String,
    pub has_saved_password: bool,
    pub updated_at_epoch: u64,
}

impl UserAccount {
    pub fn new(raw_user: &str, domain_override: &str, display_name: &str) -> Result<Self, String> {
        let (parsed_domain, parsed_username) = split_domain_username(raw_user);
        let username = parsed_username.trim().to_string();
        if username.is_empty() {
            return Err("Username cannot be empty".to_string());
        }
        let domain = if !domain_override.trim().is_empty() {
            domain_override.trim().to_string()
        } else {
            parsed_domain
        };
        let label = if display_name.trim().is_empty() {
            if domain.is_empty() {
                username.clone()
            } else {
                format!("{domain}\\{username}")
            }
        } else {
            display_name.trim().to_string()
        };

        Ok(Self {
            id: Uuid::new_v4().to_string(),
            display_name: label,
            username,
            domain,
            has_saved_password: false,
            updated_at_epoch: current_epoch_secs(),
        })
    }

    pub fn qualified_username(&self) -> String {
        if self.domain.trim().is_empty() {
            self.username.clone()
        } else {
            format!("{}\\{}", self.domain.trim(), self.username.trim())
        }
    }
}

pub fn split_domain_username(input: &str) -> (String, String) {
    let trimmed = input.trim();
    if let Some((dom, user)) = trimmed.split_once('\\') {
        (dom.trim().to_string(), user.trim().to_string())
    } else if let Some((dom, user)) = trimmed.split_once('/') {
        (dom.trim().to_string(), user.trim().to_string())
    } else {
        (String::new(), trimmed.to_string())
    }
}

pub fn current_epoch_secs() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_split_domain_username() {
        let (d, u) = split_domain_username("CONTOSO\\alice");
        assert_eq!(d, "CONTOSO");
        assert_eq!(u, "alice");

        let acct = UserAccount::new("CORP\\bob", "", "").unwrap();
        assert_eq!(acct.domain, "CORP");
        assert_eq!(acct.username, "bob");
        assert_eq!(acct.qualified_username(), "CORP\\bob");
    }
}
