use serde::{Deserialize, Serialize};
use serde_json::Value;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DittoSubscription {
    #[serde(rename = "_id")]
    pub id: String,
    pub name: String,
    pub query: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub args: Option<serde_json::Map<String, Value>>,
    #[serde(skip)]
    pub sync_subscription: Option<()>, // Placeholder for DittoSyncSubscription
}

impl DittoSubscription {
    pub fn new() -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            name: String::new(),
            query: String::new(),
            args: None,
            sync_subscription: None,
        }
    }

    pub fn from_map(value: &serde_json::Map<String, Value>) -> Self {
        Self {
            id: value["_id"].as_str().unwrap_or_default().to_string(),
            name: value["name"].as_str().unwrap_or_default().to_string(),
            query: value["query"].as_str().unwrap_or_default().to_string(),
            args: value.get("args").and_then(|v| v.as_object().cloned()),
            sync_subscription: None,
        }
    }
}

impl Default for DittoSubscription {
    fn default() -> Self {
        Self::new()
    }
}
