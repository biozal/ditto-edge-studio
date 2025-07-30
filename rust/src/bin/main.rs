use std::{path::PathBuf, sync::Arc, time::Duration};

use anyhow::{Context, Result};
use clap::Parser;

use dittolive_ditto::{fs::PersistentRoot, identity::OnlinePlayground, AppId, Ditto };
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[derive(Debug, Parser)]
pub struct Cli {
    /// The Ditto App ID this app will use to initialize Ditto
    #[clap(long, env = "DITTO_APP_ID")]
    app_id: AppId,

    /// The Online Playground token this app should use for authentication
    #[clap(long, env = "DITTO_PLAYGROUND_TOKEN")]
    token: String,

    /// Path to write logs on disk
    #[clap(long, default_value = "/tmp/edge-studio.log")]
    log: PathBuf,
}

impl Cli {
    pub fn try_init_tracing(&self) -> Result<()> {
        let logfile = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.log)
            .with_context(|| format!("failed to open logfile {}", self.log.display()))?;
        tracing_subscriber::registry()
            .with(tracing_subscriber::fmt::layer().with_writer(logfile))
            .try_init()?;
        Ok(())
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    try_init_dotenv().ok();
    let cli = Cli::parse();
    cli.try_init_tracing()?;

    let ditto = try_init_ditto(
        cli.app_id, 
        cli.token)?;

    tracing::info!(success = true, "Successul Initialized Main Ditto Pointer!");

    //TODO Start Main App Listing UI
    println!("Hello, world!");

    tracing::info!("Moving to quit");
    // Wait for shutdown to complete or timeout
    tokio::select! {
        _ = tokio::time::sleep(Duration::from_secs(2)) => {
            tracing::error!("[SHUTDOWN] Graceful shutdown timer expired, force-quitting!");
            std::process::exit(1);
        }
    }
}

fn try_init_ditto(
    app_id: AppId, 
    token: String) -> Result<Ditto> {
    
    let ditto = Ditto::builder()
        .with_root(Arc::new(PersistentRoot::from_current_exe()?))
        .with_identity(|root| OnlinePlayground::new(
            root, 
            app_id.clone(), 
            token, 
            false, // This is required to be set to false to use the correct URLs
            None
        ))?
        .build()?;

    ditto.update_transport_config(|config| {
        config.enable_all_peer_to_peer();
    });

    // Disable sync with v3 peers, required for syncing with the Ditto Cloud (BigPeer)
    _ = ditto.disable_sync_with_v3();

    // Start sync
    _ = ditto.start_sync();

    tracing::info!(%app_id, "Started Ditto!");
    Ok(ditto)
}

/// Load .env file from git repo root rather than `rust/`
fn try_init_dotenv() -> Result<()> {
    let git_toplevel_output = std::process::Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .context("failed to exec 'git rev-parse --show-toplevel'")?;
    let path = String::from_utf8(git_toplevel_output.stdout)?;
    let path = std::path::Path::new(path.trim());
    let path = path.join(".env");
    dotenvy::from_path(&path)?;
    Ok(())
}