use dittolive_ditto::prelude::*;
use std::path::PathBuf;
use std::sync::Arc;
use std::env;
use crate::ditto_config::DittoConfig;

/// Result type for Ditto operations
pub type DittoResult<T> = Result<T, DittoError>;

/// Trait for providing Ditto instances with dependency injection support
pub trait DittoProvider: Send + Sync {
    /// Initialize and return a Ditto instance
    async fn initialize(&self) -> DittoResult<Arc<Ditto>>;
    
    /// Get the storage path being used
    fn get_storage_path(&self) -> PathBuf;
    
    /// Check if the provider is configured for local-only mode
    fn is_local_only(&self) -> bool;
}

/// Local cache-only Ditto provider
pub struct LocalDittoProvider {
    config: DittoConfig,
    storage_path: PathBuf,
}

impl LocalDittoProvider {
    /// Create a new LocalDittoProvider
    pub fn new(config: DittoConfig) -> Self {
        let storage_path = Self::create_storage_path();
        Self {
            config,
            storage_path,
        }
    }
    
    /// Create the storage path: ~/Library/Containers/DittoEdgeStudio/local-app-cache
    fn create_storage_path() -> PathBuf {
        let home_dir = env::var("HOME")
            .or_else(|_| env::var("USERPROFILE"))
            .unwrap_or_else(|_| ".".to_string());
            
        PathBuf::from(home_dir)
            .join("Library")
            .join("Containers")
            .join("DittoEdgeStudio")
            .join("local-app-cache")
    }
    
    /// Configure Ditto for local-only operation
    async fn configure_local_only(ditto: &Ditto) -> DittoResult<()> {
        // Disable sync with V3
        let _ = ditto.disable_sync_with_v3();
        
        // Disable DQL strict mode - always access store directly from ditto instance
        ditto.store().execute_v2("ALTER SYSTEM SET DQL_STRICT_MODE = false").await?;
        
        // Set up sync scopes for local collections only
        let sync_scopes = serde_json::json!({
            "dittoappconfigs": "LocalPeerOnly",
            "dittosubscriptions": "LocalPeerOnly", 
            "dittoobservations": "LocalPeerOnly",
            "dittoqueryfavorites": "LocalPeerOnly",
            "dittoqueryhistory": "LocalPeerOnly"
        });
        
        ditto.store().execute_v2((
            "ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES = :syncScopes",
            serde_json::json!({ "syncScopes": sync_scopes })
        )).await?;
        
        Ok(())
    }
}

impl DittoProvider for LocalDittoProvider {
    async fn initialize(&self) -> DittoResult<Arc<Ditto>> {
        // Create the storage directory if it doesn't exist
        if let Err(e) = std::fs::create_dir_all(&self.storage_path) {
            return Err(DittoError::from(std::io::Error::new(
                std::io::ErrorKind::Other,
                format!("Failed to create storage directory: {}", e)
            )));
        }
        
        // Get app ID and playground token from environment
        let app_id = AppId::from_env("DITTO_APP_ID")?;
        let playground_token = env::var("DITTO_PLAYGROUND_TOKEN")
            .map_err(|_| DittoError::from(std::io::Error::new(
                std::io::ErrorKind::Other,
                "DITTO_PLAYGROUND_TOKEN is required"
            )))?;
        let auth_url = env::var("DITTO_AUTH_URL").ok();
        
        // Create persistence root for local storage
        let persistence_root = Arc::new(PersistentRoot::new(&self.storage_path)?);
        
        // Use the recommended builder API with OnlinePlayground identity
        let ditto = Ditto::builder()
            .with_root(persistence_root)
            .with_identity(|ditto_root| {
                // Use OnlinePlayground identity with playground token
                // enableDittoCloudSync: false for local-only operation
                // customAuthURL: from environment
                identity::OnlinePlayground::new(
                    ditto_root, 
                    app_id, 
                    playground_token.clone(),
                    false,  // enableDittoCloudSync: false for local-only
                    auth_url.as_deref()  // customAuthURL
                )
            })?
            .build()?;
            
        // Configure for local-only operation
        Self::configure_local_only(&ditto).await?;
        
        // Start sync
        ditto.start_sync()?;
        
        Ok(Arc::new(ditto))
    }
    
    fn get_storage_path(&self) -> PathBuf {
        self.storage_path.clone()
    }
    
    fn is_local_only(&self) -> bool {
        true
    }
}

/// Mock implementation for testing
pub struct MockDittoProvider {
    pub should_fail: bool,
    pub storage_path: PathBuf,
}

impl MockDittoProvider {
    pub fn new() -> Self {
        Self {
            should_fail: false,
            storage_path: PathBuf::from("/tmp/mock-ditto"),
        }
    }
    
    pub fn with_failure() -> Self {
        Self {
            should_fail: true,
            storage_path: PathBuf::from("/tmp/mock-ditto"),
        }
    }
}

impl DittoProvider for MockDittoProvider {
    async fn initialize(&self) -> DittoResult<Arc<Ditto>> {
        if self.should_fail {
            return Err(DittoError::from(std::io::Error::new(
                std::io::ErrorKind::Other,
                "Mock initialization failure"
            )));
        }
        
        // For testing, we can't create a real Ditto instance without valid config
        // Return an error that indicates mock success
        Err(DittoError::from(std::io::Error::new(
            std::io::ErrorKind::Other,
            "Mock provider - would return Ditto instance"
        )))
    }
    
    fn get_storage_path(&self) -> PathBuf {
        self.storage_path.clone()
    }
    
    fn is_local_only(&self) -> bool {
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ditto_config::DittoConfig;

    #[test]
    fn test_local_ditto_provider_creation() {
        let config = DittoConfig {
            app_id: "test-app-id".to_string(),
            playground_token: "test-token".to_string(),
            auth_url: "https://test.auth.url".to_string(),
            websocket_url: "wss://test.websocket.url".to_string(),
        };
        
        let provider = LocalDittoProvider::new(config);
        
        assert!(provider.is_local_only());
        assert!(provider.get_storage_path().to_string_lossy().contains("DittoEdgeStudio"));
        assert!(provider.get_storage_path().to_string_lossy().contains("local-app-cache"));
    }
    
    #[test]
    fn test_storage_path_creation() {
        let path = LocalDittoProvider::create_storage_path();
        let path_str = path.to_string_lossy();
        
        assert!(path_str.contains("Library"));
        assert!(path_str.contains("Containers"));
        assert!(path_str.contains("DittoEdgeStudio"));
        assert!(path_str.contains("local-app-cache"));
    }
    
    #[tokio::test]
    async fn test_mock_provider_success() {
        let mock = MockDittoProvider::new();
        
        assert!(mock.is_local_only());
        assert_eq!(mock.get_storage_path(), PathBuf::from("/tmp/mock-ditto"));
        
        // Mock should "fail" with a specific message indicating it would work
        let result = mock.initialize().await;
        assert!(result.is_err());
        let error_msg = format!("{}", result.unwrap_err());
        assert!(error_msg.contains("Mock provider"));
    }
    
    #[tokio::test]
    async fn test_mock_provider_failure() {
        let mock = MockDittoProvider::with_failure();
        
        let result = mock.initialize().await;
        assert!(result.is_err());
        let error_msg = format!("{}", result.unwrap_err());
        assert!(error_msg.contains("Mock initialization failure"));
    }
}