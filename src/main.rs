use std::sync::Arc;

use rdp_client_ut::app_controller::AppController;
use rdp_client_ut::storage::{CredentialVault, StorageDatabase};

fn main() {
    let _ = tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .try_init();

    let args: Vec<String> = std::env::args().collect();
    if args.iter().any(|a| a == "--self-test" || a == "--version") {
        let db = StorageDatabase::open_default().expect("storage db");
        let vault = CredentialVault::open_default().expect("credential vault");
        let ctrl = AppController::new(
            db,
            vault,
            Arc::new(|json_str, _| {
                println!("{json_str}");
            }),
        );
        ctrl.emit_state_snapshot();
        return;
    }

    println!("rdp-client-ut Rust backend ready. Run the Qt/QML shell binary `rdp-client-ut` on Ubuntu Touch.");
}
