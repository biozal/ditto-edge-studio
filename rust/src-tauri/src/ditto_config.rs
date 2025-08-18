use serde::{Deserialize, Serialize};
use std::env;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DittoConfig {
    pub app_id: String,
    pub playground_token: String,
    pub auth_url: String,
    pub websocket_url: String,
}

impl DittoConfig {
    /// Load configuration from environment variables
    pub fn from_env() -> Result<Self, String> {
        Self::from_env_internal(true)
    }

    /// Internal method with option to skip dotenv loading (for testing)
    fn from_env_internal(load_dotenv: bool) -> Result<Self, String> {
        // Load .env file if it exists (unless disabled for testing)
        if load_dotenv {
            let mut loaded = false;
            
            // First try to load from bundled resources (for production app)
            if let Ok(exe_path) = std::env::current_exe() {
                if let Some(exe_dir) = exe_path.parent() {
                    // For macOS app bundle, check multiple resource locations
                    let bundle_paths = vec![
                        exe_dir.join("../Resources/.env"),
                        exe_dir.join("../Resources/_up_/.env"),  // Tauri bundles relative paths in _up_
                    ];
                    
                    for bundle_env_path in bundle_paths {
                        if bundle_env_path.exists() {
                            if dotenv::from_path(&bundle_env_path).is_ok() {
                                loaded = true;
                                break;
                            }
                        }
                    }
                }
            }
            
            // If not loaded from bundle, try development locations
            if !loaded {
                let current_dir = std::env::current_dir().unwrap_or_else(|_| std::path::PathBuf::from("."));
                let possible_paths = vec![
                    current_dir.join(".env"),
                    current_dir.parent().unwrap_or(&current_dir).join(".env"),
                    std::path::PathBuf::from(".env"),
                    std::path::PathBuf::from("../.env"),
                ];
                
                for path in possible_paths {
                    if path.exists() {
                        if dotenv::from_path(&path).is_ok() {
                            loaded = true;
                            break;
                        }
                    }
                }
            }
            
            // Also try the default dotenv behavior as fallback
            if !loaded {
                dotenv::dotenv().ok();
            }
        }

        // Debug info will be returned via a separate command
        
        // Required fields exactly as in quickstart
        let app_id = env::var("DITTO_APP_ID")
            .map_err(|_| "DITTO_APP_ID is required. Please set it in your .env file")?;
        
        let playground_token = env::var("DITTO_PLAYGROUND_TOKEN")
            .map_err(|_| "DITTO_PLAYGROUND_TOKEN is required. Please set it in your .env file")?;
        
        let auth_url = env::var("DITTO_AUTH_URL")
            .map_err(|_| "DITTO_AUTH_URL is required. Please set it in your .env file")?;
        
        let websocket_url = env::var("DITTO_WEBSOCKET_URL")
            .map_err(|_| "DITTO_WEBSOCKET_URL is required. Please set it in your .env file")?;

        // Validate that required fields are not empty
        if app_id.trim().is_empty() {
            return Err("DITTO_APP_ID cannot be empty".to_string());
        }
        if playground_token.trim().is_empty() {
            return Err("DITTO_PLAYGROUND_TOKEN cannot be empty".to_string());
        }
        if auth_url.trim().is_empty() {
            return Err("DITTO_AUTH_URL cannot be empty".to_string());
        }
        if websocket_url.trim().is_empty() {
            return Err("DITTO_WEBSOCKET_URL cannot be empty".to_string());
        }

        Ok(DittoConfig {
            app_id,
            playground_token,
            auth_url,
            websocket_url,
        })
    }
}

/// Tauri command to get the current configuration
#[tauri::command]
pub fn get_ditto_config() -> Result<DittoConfig, String> {
    DittoConfig::from_env()
}

/// Debug command to check environment and .env file loading
#[tauri::command]
pub fn debug_env_loading() -> String {
    let current_dir = std::env::current_dir().unwrap_or_else(|_| std::path::PathBuf::from("."));
    let mut debug_info = Vec::new();
    
    debug_info.push(format!("Current working directory: {:?}", current_dir));
    
    // Check executable path and bundled resources
    if let Ok(exe_path) = std::env::current_exe() {
        debug_info.push(format!("Executable path: {:?}", exe_path));
        if let Some(exe_dir) = exe_path.parent() {
            let bundle_env_path = exe_dir.join("../Resources/.env");
            debug_info.push(format!("Bundle resource path: {:?}", bundle_env_path));
        }
    }
    
    // Check possible .env file locations
    let mut possible_paths = vec![];
    
    // Add bundle resource paths first
    if let Ok(exe_path) = std::env::current_exe() {
        if let Some(exe_dir) = exe_path.parent() {
            possible_paths.push(exe_dir.join("../Resources/.env"));
            possible_paths.push(exe_dir.join("../Resources/_up_/.env"));  // Tauri bundles relative paths in _up_
        }
    }
    
    // Add development paths
    possible_paths.extend(vec![
        current_dir.join(".env"),
        current_dir.parent().unwrap_or(&current_dir).join(".env"),
        std::path::PathBuf::from(".env"),
        std::path::PathBuf::from("../.env"),
    ]);
    
    debug_info.push("Checking .env file locations:".to_string());
    for path in &possible_paths {
        if path.exists() {
            debug_info.push(format!("  ✅ Found: {:?}", path));
        } else {
            debug_info.push(format!("  ❌ Not found: {:?}", path));
        }
    }
    
    // Try loading .env and check environment variables
    dotenv::dotenv().ok();
    for path in possible_paths {
        if path.exists() {
            if let Err(e) = dotenv::from_path(&path) {
                debug_info.push(format!("Failed to load .env from {:?}: {}", path, e));
            } else {
                debug_info.push(format!("Successfully loaded .env from: {:?}", path));
                break;
            }
        }
    }
    
    // Check environment variables
    debug_info.push("\nEnvironment variables:".to_string());
    debug_info.push(format!("  DITTO_APP_ID: {:?}", env::var("DITTO_APP_ID")));
    debug_info.push(format!("  DITTO_PLAYGROUND_TOKEN: {:?}", env::var("DITTO_PLAYGROUND_TOKEN")));
    debug_info.push(format!("  DITTO_AUTH_URL: {:?}", env::var("DITTO_AUTH_URL")));
    debug_info.push(format!("  DITTO_WEBSOCKET_URL: {:?}", env::var("DITTO_WEBSOCKET_URL")));
    
    debug_info.join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;

    #[test]
    fn test_env_loading_without_env_file() {
        // Clear environment variables to test error handling
        env::remove_var("DITTO_APP_ID");
        env::remove_var("DITTO_PLAYGROUND_TOKEN");
        env::remove_var("DITTO_AUTH_URL");
        env::remove_var("DITTO_WEBSOCKET_URL");

        let result = DittoConfig::from_env_internal(false);  // Skip dotenv loading
        assert!(result.is_err());
        let error_msg = result.unwrap_err();
        println!("Error message: {}", error_msg);
        // Should fail because at least one required variable is missing
        assert!(error_msg.contains("is required"));
    }

    #[test]
    fn test_env_loading_with_empty_values() {
        // Set all valid values first
        env::set_var("DITTO_APP_ID", "valid-id");
        env::set_var("DITTO_PLAYGROUND_TOKEN", "valid-token");
        env::set_var("DITTO_AUTH_URL", "valid-url");
        env::set_var("DITTO_WEBSOCKET_URL", "valid-ws-url");
        
        // Now set one to empty to test validation
        env::set_var("DITTO_APP_ID", "");

        let result = DittoConfig::from_env_internal(false);  // Skip dotenv loading
        assert!(result.is_err());
        let error_msg = result.unwrap_err();
        println!("Error message: {}", error_msg);
        assert!(error_msg.contains("cannot be empty"));
    }

    #[test]
    fn test_env_loading_with_valid_values() {
        // Set valid values
        env::set_var("DITTO_APP_ID", "test-app-id");
        env::set_var("DITTO_PLAYGROUND_TOKEN", "test-token");
        env::set_var("DITTO_AUTH_URL", "https://test.auth.url");
        env::set_var("DITTO_WEBSOCKET_URL", "wss://test.websocket.url");


        let result = DittoConfig::from_env_internal(false);  // Skip dotenv loading
        if let Err(e) = &result {
            println!("Unexpected error: {}", e);
        }
        assert!(result.is_ok());
        
        let config = result.unwrap();
        assert_eq!(config.app_id, "test-app-id");
        assert_eq!(config.playground_token, "test-token");
        assert_eq!(config.auth_url, "https://test.auth.url");
        assert_eq!(config.websocket_url, "wss://test.websocket.url");
    }
}