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
    if args.iter().any(|a| a == "--sentry-check") {
        let db = StorageDatabase::open_default().expect("storage db");
        if !db.load_settings().report_errors {
            eprintln!("Report Errors is disabled; no verification report was sent.");
            std::process::exit(2);
        }
        let vault = CredentialVault::open_default().expect("credential vault");
        let _controller = AppController::new(db, vault, Arc::new(|_, _| {}));
        let Some(reporter) = rdp_client_ut::error_reporting::current().filter(|reporter| reporter.is_configured()) else {
            eprintln!("Sentry could not be initialized; no verification error was triggered.");
            std::process::exit(3);
        };
        // Explicit developer verification only. No user input, data, or secrets.
        let _ = std::panic::catch_unwind(|| panic!("Sentry setup verification"));
        let flushed = reporter.flush(std::time::Duration::from_secs(10));
        if !flushed { std::process::exit(3); }
        println!("Synthetic Rust panic captured through the application panic hook.");
        return;
    }
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
