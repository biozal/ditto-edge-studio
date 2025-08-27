use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DittoAppConfig {
    #[serde(rename = "_id")]
    pub id: String,
    pub name: String,
    #[serde(rename = "appId")]
    pub app_id: String,
    #[serde(rename = "authToken")]
    pub auth_token: String,
    #[serde(rename = "authUrl")]
    pub auth_url: String,
    #[serde(rename = "websocketUrl")]
    pub websocket_url: String,
    #[serde(rename = "httpApiUrl")]
    pub http_api_url: String,
    #[serde(rename = "httpApiKey")]
    pub http_api_key: String,
    #[serde(rename = "mongoDbConnectionString")]
    pub mongo_db_connection_string: String,
    pub mode: String,
    #[serde(rename = "allowUntrustedCerts")]
    pub allow_untrusted_certs: bool,
}

impl DittoAppConfig {
    pub fn new(
        name: String,
        app_id: String,
        auth_token: String,
        auth_url: String,
        websocket_url: String,
        http_api_url: String,
        http_api_key: String,
        mongo_db_connection_string: String,
        mode: String,
        allow_untrusted_certs: bool,
    ) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            name,
            app_id,
            auth_token,
            auth_url,
            websocket_url,
            http_api_url,
            http_api_key,
            mongo_db_connection_string,
            mode,
            allow_untrusted_certs,
        }
    }
}