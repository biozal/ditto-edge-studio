mod ditto_config;
mod ditto_provider;
mod logging;
mod ditto_app_config;
mod repositories;

use ditto_config::{get_ditto_config, debug_env_loading};
use ditto_provider::{DittoProvider, LocalDittoProvider};
use logging::{get_logs, clear_logs, get_logs_as_string, get_log_count, init_log_cache, log_info, log_error};
use ditto_app_config::DittoAppConfig;
use repositories::DittoLocalCacheRepository;
use tauri::{Manager, WebviewUrl, WebviewWindowBuilder};
use dittolive_ditto::prelude::*;
use std::sync::Arc;
use tokio::sync::Mutex;
use tauri::State;

// Global state for the Ditto instance
type DittoState = Arc<Mutex<Option<Arc<Ditto>>>>;

// Learn more about Tauri commands at https://tauri.app/develop/calling-rust/
#[tauri::command]
fn greet(name: &str) -> String {
    format!("Hello, {}! You've been greeted from Rust!", name)
}

// Test command to verify .env configuration is properly loaded
#[tauri::command]
fn check_env_config() -> Result<String, String> {
    match get_ditto_config() {
        Ok(config) => Ok(format!(
            "Environment configuration loaded successfully!\nApp ID: {}\nAuth URL: {}\nWebSocket URL: {}",
            config.app_id,
            config.auth_url,
            config.websocket_url
        )),
        Err(e) => Err(e)
    }
}

// Initialize Ditto with local cache configuration
#[tauri::command]
async fn initialize_ditto(state: State<'_, DittoState>) -> Result<String, String> {
    log_info("ditto", "Starting Ditto initialization");
    
    // Load configuration
    let config = match get_ditto_config() {
        Ok(cfg) => {
            log_info("ditto", &format!("Configuration loaded for app ID: {}", cfg.app_id));
            cfg
        }
        Err(e) => {
            log_error("ditto", &format!("Failed to load configuration: {}", e));
            return Err(e);
        }
    };
    
    // Create local provider
    let provider = LocalDittoProvider::new(config);
    log_info("ditto", &format!("Storage path: {}", provider.get_storage_path().display()));
    
    // Initialize Ditto
    let ditto = match provider.initialize().await {
        Ok(d) => {
            log_info("ditto", "Ditto instance initialized successfully");
            d
        }
        Err(e) => {
            let error_msg = format!("Failed to initialize Ditto: {}", e);
            log_error("ditto", &error_msg);
            return Err(error_msg);
        }
    };
    
    // Store in global state
    let mut ditto_state = state.lock().await;
    *ditto_state = Some(ditto);
    
    let success_msg = format!(
        "Ditto initialized successfully!\nStorage path: {}\nLocal-only mode: {}",
        provider.get_storage_path().display(),
        provider.is_local_only()
    );
    
    log_info("ditto", "Ditto initialization completed successfully");
    Ok(success_msg)
}

// Open the logs window
#[tauri::command]
async fn open_logs_window(app: tauri::AppHandle) -> Result<(), String> {
    // Check if logs window already exists
    if let Some(_window) = app.get_webview_window("logs") {
        // If it exists, just focus it
        _window.set_focus().map_err(|e| format!("Failed to focus logs window: {}", e))?;
        return Ok(());
    }

    // Create new logs window
    let _logs_window = WebviewWindowBuilder::new(
        &app,
        "logs",
        WebviewUrl::App("index.html".into())
    )
    .title("Application Logs")
    .inner_size(1000.0, 700.0)
    .min_inner_size(600.0, 400.0)
    .center()
    .resizable(true)
    .initialization_script("window.__IS_LOGS_WINDOW__ = true;")
    .build()
    .map_err(|e| format!("Failed to create logs window: {}", e))?;

    log_info("app", "Logs window opened");
    Ok(())
}

// Check if Ditto is initialized
#[tauri::command]
async fn is_ditto_initialized(state: State<'_, DittoState>) -> Result<bool, String> {
    let ditto_state = state.lock().await;
    Ok(ditto_state.is_some())
}

// Get Ditto status information
#[tauri::command]
async fn get_ditto_status(state: State<'_, DittoState>) -> Result<String, String> {
    let ditto_state = state.lock().await;
    
    match ditto_state.as_ref() {
        Some(_) => {
            // Load config to show status
            let config = get_ditto_config()?;
            let app_id = config.app_id.clone();
            let provider = LocalDittoProvider::new(config);
            
            Ok(format!(
                "Ditto Status: Initialized\nStorage Path: {}\nLocal-only Mode: {}\nApp ID: {}",
                provider.get_storage_path().display(),
                provider.is_local_only(),
                app_id
            ))
        }
        None => Ok("Ditto Status: Not Initialized".to_string())
    }
}

// Save (add or update) a Ditto app configuration using INSERT ON CONFLICT
#[tauri::command]
async fn save_ditto_app_config(state: State<'_, DittoState>, config: DittoAppConfig) -> Result<String, String> {
    let ditto_state = state.lock().await;
    let ditto = match ditto_state.as_ref() {
        Some(d) => d.clone(),
        None => {
            let error_msg = "Ditto not initialized".to_string();
            log_error("app_config", &error_msg);
            return Err(error_msg);
        }
    };
    drop(ditto_state);

    let repository = DittoLocalCacheRepository::new(ditto);
    repository.save_app_config(config).await
}

// Add a new Ditto app configuration to the database (legacy - use save_ditto_app_config)
#[tauri::command]
async fn add_ditto_app_config(state: State<'_, DittoState>, config: DittoAppConfig) -> Result<String, String> {
    // Ensure Ditto is initialized
    let ditto_state = state.lock().await;
    let ditto = match ditto_state.as_ref() {
        Some(d) => d.clone(),
        None => {
            let error_msg = "Ditto not initialized".to_string();
            log_error("app_config", &error_msg);
            return Err(error_msg);
        }
    };
    drop(ditto_state);

    // Use repository to handle database operations
    let repository = DittoLocalCacheRepository::new(ditto);
    repository.add_app_config(config).await
}

// Update an existing Ditto app configuration
#[tauri::command]
async fn update_ditto_app_config(state: State<'_, DittoState>, config: DittoAppConfig) -> Result<String, String> {
    let ditto_state = state.lock().await;
    let ditto = match ditto_state.as_ref() {
        Some(d) => d.clone(),
        None => {
            let error_msg = "Ditto not initialized".to_string();
            log_error("app_config", &error_msg);
            return Err(error_msg);
        }
    };
    drop(ditto_state);

    let repository = DittoLocalCacheRepository::new(ditto);
    repository.update_app_config(config).await
}

// Delete a Ditto app configuration
#[tauri::command]
async fn delete_ditto_app_config(state: State<'_, DittoState>, config_id: String) -> Result<String, String> {
    let ditto_state = state.lock().await;
    let ditto = match ditto_state.as_ref() {
        Some(d) => d.clone(),
        None => {
            let error_msg = "Ditto not initialized".to_string();
            log_error("app_config", &error_msg);
            return Err(error_msg);
        }
    };
    drop(ditto_state);

    let repository = DittoLocalCacheRepository::new(ditto);
    repository.delete_app_config(config_id).await
}

// Get all Ditto app configurations
#[tauri::command]
async fn get_all_ditto_app_configs(state: State<'_, DittoState>) -> Result<Vec<DittoAppConfig>, String> {
    let ditto_state = state.lock().await;
    let ditto = match ditto_state.as_ref() {
        Some(d) => d.clone(),
        None => {
            let error_msg = "Ditto not initialized".to_string();
            log_error("app_config", &error_msg);
            return Err(error_msg);
        }
    };
    drop(ditto_state);

    let repository = DittoLocalCacheRepository::new(ditto);
    repository.get_all_app_configs().await
}

// Register observer for app configs using observer v2 API
#[tauri::command]
async fn register_app_config_observer(state: State<'_, DittoState>, app: tauri::AppHandle) -> Result<String, String> {
    let ditto_state = state.lock().await;
    let ditto = match ditto_state.as_ref() {
        Some(d) => d.clone(),
        None => {
            let error_msg = "Ditto not initialized".to_string();
            log_error("observer", &error_msg);
            return Err(error_msg);
        }
    };
    drop(ditto_state);

    let repository = DittoLocalCacheRepository::new(ditto);
    repository.register_app_config_observer(app).await
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    // Initialize the logging cache with 1000 max entries
    init_log_cache(1000);
    log_info("app", "Ditto Edge Studio starting up");
    
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .manage(DittoState::new(Mutex::new(None)))
        .setup(|app| {
            // Configure macOS window appearance
            #[cfg(target_os = "macos")]
            {
                use tauri::TitleBarStyle;
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.set_title_bar_style(TitleBarStyle::Transparent);
                }
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            greet,
            check_env_config,
            get_ditto_config,
            debug_env_loading,
            initialize_ditto,
            is_ditto_initialized,
            get_ditto_status,
            get_logs,
            clear_logs,
            get_logs_as_string,
            get_log_count,
            open_logs_window,
            save_ditto_app_config,
            add_ditto_app_config,
            update_ditto_app_config,
            delete_ditto_app_config,
            get_all_ditto_app_configs,
            register_app_config_observer
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
