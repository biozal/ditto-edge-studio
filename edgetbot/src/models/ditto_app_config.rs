use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DittoAppConfig {
    #[serde(rename = "_id")]
    pub id: String,
    pub name: String,
    pub app_id: String,
    pub auth_token: String,
    pub auth_url: String,
    pub websocket_url: String,
    pub http_api_url: String,
    pub http_api_key: String,
    pub mode: String,
}

impl DittoAppConfig {
    pub fn new() -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            name: String::new(),
            app_id: String::new(),
            auth_token: String::new(),
            auth_url: String::new(),
            websocket_url: String::new(),
            http_api_url: String::new(),
            http_api_key: String::new(),
            mode: "online".to_string(),
        }
    }
}

impl Default for DittoAppConfig {
    fn default() -> Self {
        Self::new()
    }
}
