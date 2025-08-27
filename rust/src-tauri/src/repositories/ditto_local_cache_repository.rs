use dittolive_ditto::prelude::*;
use std::sync::Arc;
use crate::ditto_app_config::DittoAppConfig;
use crate::logging::{log_info, log_error};
use tauri::Emitter;

/// Repository for managing local cache database operations
pub struct DittoLocalCacheRepository {
    ditto: Arc<Ditto>,
}

impl DittoLocalCacheRepository {
    /// Create a new repository instance
    pub fn new(ditto: Arc<Ditto>) -> Self {
        Self { ditto }
    }

    /// Add or update a Ditto app configuration using INSERT ON CONFLICT
    pub async fn save_app_config(&self, config: DittoAppConfig) -> Result<String, String> {
        log_info("app_config", &format!("Saving app config: {}", config.name));
        
        // Use INSERT ON CONFLICT DO UPDATE for upsert functionality
        let query = "INSERT INTO dittoappconfigs VALUES (:config) ON ID CONFLICT DO UPDATE";
        
        // Create config map matching the SwiftUI implementation
        let config_map = serde_json::json!({
            "_id": config.id,
            "name": config.name,
            "appId": config.app_id,
            "authToken": config.auth_token,
            "authUrl": config.auth_url,
            "websocketUrl": config.websocket_url,
            "httpApiUrl": config.http_api_url,
            "httpApiKey": config.http_api_key,
            "mode": config.mode,
            "allowUntrustedCerts": config.allow_untrusted_certs,
            "mongoDbConnectionString": config.mongo_db_connection_string
        });
        
        let arguments = serde_json::json!({
            "config": config_map
        });
        
        // ✅ CORRECT - Always access store directly from ditto instance, using v2 API
        match self.ditto.store().execute_v2((query, arguments)).await {
            Ok(result) => {
                // Validate that document was actually saved by checking mutated document IDs
                let mutated_ids = result.mutated_document_ids();
                if mutated_ids.is_empty() {
                    let error_msg = format!("No documents were saved for app config: {}", config.name);
                    log_error("app_config", &error_msg);
                    Err(error_msg)
                } else {
                    let document_id = mutated_ids[0].to_string();
                    let success_msg = format!("Successfully saved app config '{}' with document ID: {}", config.name, document_id);
                    log_info("app_config", &success_msg);
                    Ok(success_msg)
                }
            }
            Err(e) => {
                let error_msg = format!("Failed to save app config: {}", e);
                log_error("app_config", &error_msg);
                Err(error_msg)
            }
        }
    }

    /// Add a new Ditto app configuration (legacy method - use save_app_config instead)
    pub async fn add_app_config(&self, config: DittoAppConfig) -> Result<String, String> {
        self.save_app_config(config).await
    }

    /// Update an existing Ditto app configuration (legacy method - use save_app_config instead)
    pub async fn update_app_config(&self, config: DittoAppConfig) -> Result<String, String> {
        self.save_app_config(config).await
    }

    /// Delete a Ditto app configuration
    pub async fn delete_app_config(&self, config_id: String) -> Result<String, String> {
        log_info("app_config", &format!("Deleting app config with ID: {}", config_id));
        
        let query = "DELETE FROM dittoappconfigs WHERE _id = :id";
        let arguments = serde_json::json!({ "id": config_id });
        
        // ✅ CORRECT - Always access store directly from ditto instance, using v2 API
        match self.ditto.store().execute_v2((query, arguments)).await {
            Ok(result) => {
                // Validate that document was actually deleted by checking mutated document IDs
                let mutated_ids = result.mutated_document_ids();
                if mutated_ids.is_empty() {
                    let error_msg = format!("No documents were deleted for app config ID: {} (document may not exist)", config_id);
                    log_error("app_config", &error_msg);
                    Err(error_msg)
                } else {
                    let document_id = mutated_ids[0].to_string();
                    let success_msg = format!("Successfully deleted app config with document ID: {}", document_id);
                    log_info("app_config", &success_msg);
                    Ok(success_msg)
                }
            }
            Err(e) => {
                let error_msg = format!("Failed to delete app config: {}", e);
                log_error("app_config", &error_msg);
                Err(error_msg)
            }
        }
    }

    /// Get all app configurations
    pub async fn get_all_app_configs(&self) -> Result<Vec<DittoAppConfig>, String> {
        log_info("app_config", "Fetching all app configs");
        
        let query = "SELECT * FROM dittoappconfigs ORDER BY name";
        
        // ✅ CORRECT - Always access store directly from ditto instance, using v2 API
        match self.ditto.store().execute_v2(query).await {
            Ok(result) => {
                let mut app_configs = Vec::new();
                
                // Parse query results into DittoAppConfig structs
                for item in result.iter() {
                    match item.deserialize_value::<DittoAppConfig>() {
                        Ok(config) => {
                            log_info("app_config", &format!("Parsed app config: {}", config.name));
                            app_configs.push(config);
                        }
                        Err(e) => {
                            log_error("app_config", &format!("Failed to deserialize app config: {}", e));
                            // Continue processing other items instead of failing completely
                        }
                    }
                }
                
                log_info("app_config", &format!("Successfully fetched {} app configs", app_configs.len()));
                Ok(app_configs)
            }
            Err(e) => {
                let error_msg = format!("Failed to fetch app configs: {}", e);
                log_error("app_config", &error_msg);
                Err(error_msg)
            }
        }
    }

    /// Register observer for app configs using observer v2 API
    pub async fn register_app_config_observer(&self, app: tauri::AppHandle) -> Result<String, String> {
        log_info("observer", "Registering app config observer");
        
        let query = "SELECT * FROM dittoappconfigs ORDER BY name";
        
        // Register observer v2 with callback
        let observer_handle = self.ditto.store().register_observer_v2(query, move |query_result| {
            log_info("observer", "App config observer triggered - data changed");
            
            let mut app_configs = Vec::new();
            
            // Parse query results into DittoAppConfig structs
            for item in query_result.iter() {
                match item.deserialize_value::<DittoAppConfig>() {
                    Ok(config) => {
                        log_info("observer", &format!("Observer parsed app config: {}", config.name));
                        app_configs.push(config);
                    }
                    Err(e) => {
                        log_error("observer", &format!("Observer failed to deserialize app config: {}", e));
                        // Continue processing other items instead of failing completely
                    }
                }
            }
            
            log_info("observer", &format!("Observer emitting {} app configs", app_configs.len()));
            
            // Emit event to frontend with the actual parsed data
            if let Err(e) = app.emit("app-configs-updated", &app_configs) {
                log_error("observer", &format!("Failed to emit app configs update: {}", e));
            } else {
                log_info("observer", "Successfully emitted app configs update to frontend");
            }
        }).map_err(|e| format!("Failed to register observer: {}", e))?;
        
        // Store the observer handle (in a real app, you'd want to manage this lifecycle)
        // For now, we'll let it live for the duration of the app
        std::mem::forget(observer_handle);
        
        let success_msg = "App config observer registered successfully".to_string();
        log_info("observer", &success_msg);
        Ok(success_msg)
    }
}