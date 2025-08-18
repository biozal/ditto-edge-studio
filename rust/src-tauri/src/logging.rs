use serde::{Deserialize, Serialize};
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use chrono::{DateTime, Utc};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogEntry {
    pub timestamp: DateTime<Utc>,
    pub level: LogLevel,
    pub target: String,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum LogLevel {
    Error,
    Warn,
    Info,
    Debug,
    Trace,
}

impl LogLevel {
    pub fn as_str(&self) -> &'static str {
        match self {
            LogLevel::Error => "ERROR",
            LogLevel::Warn => "WARN",
            LogLevel::Info => "INFO",
            LogLevel::Debug => "DEBUG",
            LogLevel::Trace => "TRACE",
        }
    }
}

impl std::fmt::Display for LogLevel {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

/// In-memory log cache that stores log entries in a circular buffer
#[derive(Debug)]
pub struct LogCache {
    entries: Arc<Mutex<VecDeque<LogEntry>>>,
    max_entries: usize,
}

impl LogCache {
    /// Create a new log cache with a maximum number of entries
    pub fn new(max_entries: usize) -> Self {
        Self {
            entries: Arc::new(Mutex::new(VecDeque::with_capacity(max_entries))),
            max_entries,
        }
    }

    /// Add a log entry to the cache
    pub fn add_entry(&self, level: LogLevel, target: &str, message: &str) {
        let entry = LogEntry {
            timestamp: Utc::now(),
            level,
            target: target.to_string(),
            message: message.to_string(),
        };

        if let Ok(mut entries) = self.entries.lock() {
            // If we're at capacity, remove the oldest entry
            if entries.len() >= self.max_entries {
                entries.pop_front();
            }
            entries.push_back(entry);
        }
    }

    /// Get all log entries as a vector
    pub fn get_entries(&self) -> Vec<LogEntry> {
        if let Ok(entries) = self.entries.lock() {
            entries.iter().cloned().collect()
        } else {
            Vec::new()
        }
    }

    /// Clear all log entries
    pub fn clear(&self) {
        if let Ok(mut entries) = self.entries.lock() {
            entries.clear();
        }
    }

    /// Get the number of log entries currently stored
    pub fn len(&self) -> usize {
        if let Ok(entries) = self.entries.lock() {
            entries.len()
        } else {
            0
        }
    }

    /// Check if the cache is empty
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Convert all log entries to a formatted string for file export
    pub fn to_formatted_string(&self) -> String {
        let entries = self.get_entries();
        let mut result = String::new();
        
        for entry in entries {
            result.push_str(&format!(
                "[{}] {} [{}] {}\n",
                entry.timestamp.format("%Y-%m-%d %H:%M:%S%.3f UTC"),
                entry.level,
                entry.target,
                entry.message
            ));
        }
        
        result
    }
}

impl Clone for LogCache {
    fn clone(&self) -> Self {
        Self {
            entries: Arc::clone(&self.entries),
            max_entries: self.max_entries,
        }
    }
}

/// Global log cache instance
static LOG_CACHE: std::sync::OnceLock<LogCache> = std::sync::OnceLock::new();

/// Initialize the global log cache
pub fn init_log_cache(max_entries: usize) {
    LOG_CACHE.set(LogCache::new(max_entries)).ok();
}

/// Get a reference to the global log cache
pub fn get_log_cache() -> &'static LogCache {
    LOG_CACHE.get().expect("Log cache not initialized")
}

/// Log an error message
pub fn log_error(target: &str, message: &str) {
    if let Some(cache) = LOG_CACHE.get() {
        cache.add_entry(LogLevel::Error, target, message);
    }
    eprintln!("[ERROR] [{}] {}", target, message);
}

/// Log a warning message
pub fn log_warn(target: &str, message: &str) {
    if let Some(cache) = LOG_CACHE.get() {
        cache.add_entry(LogLevel::Warn, target, message);
    }
    println!("[WARN] [{}] {}", target, message);
}

/// Log an info message
pub fn log_info(target: &str, message: &str) {
    if let Some(cache) = LOG_CACHE.get() {
        cache.add_entry(LogLevel::Info, target, message);
    }
    println!("[INFO] [{}] {}", target, message);
}

/// Log a debug message
pub fn log_debug(target: &str, message: &str) {
    if let Some(cache) = LOG_CACHE.get() {
        cache.add_entry(LogLevel::Debug, target, message);
    }
    #[cfg(debug_assertions)]
    println!("[DEBUG] [{}] {}", target, message);
}

/// Log a trace message
pub fn log_trace(target: &str, message: &str) {
    if let Some(cache) = LOG_CACHE.get() {
        cache.add_entry(LogLevel::Trace, target, message);
    }
    #[cfg(debug_assertions)]
    println!("[TRACE] [{}] {}", target, message);
}

/// Tauri commands for log management
#[tauri::command]
pub fn get_logs() -> Vec<LogEntry> {
    get_log_cache().get_entries()
}

#[tauri::command]
pub fn clear_logs() -> Result<(), String> {
    get_log_cache().clear();
    log_info("logging", "Logs cleared by user");
    Ok(())
}

#[tauri::command]
pub fn get_logs_as_string() -> String {
    get_log_cache().to_formatted_string()
}

#[tauri::command]
pub fn get_log_count() -> usize {
    get_log_cache().len()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_log_cache_basic_functionality() {
        let cache = LogCache::new(3);
        
        // Test adding entries
        cache.add_entry(LogLevel::Info, "test", "First message");
        cache.add_entry(LogLevel::Warn, "test", "Second message");
        cache.add_entry(LogLevel::Error, "test", "Third message");
        
        assert_eq!(cache.len(), 3);
        
        let entries = cache.get_entries();
        assert_eq!(entries[0].message, "First message");
        assert_eq!(entries[1].message, "Second message");
        assert_eq!(entries[2].message, "Third message");
    }

    #[test]
    fn test_log_cache_circular_buffer() {
        let cache = LogCache::new(2);
        
        // Add more entries than capacity
        cache.add_entry(LogLevel::Info, "test", "First message");
        cache.add_entry(LogLevel::Info, "test", "Second message");
        cache.add_entry(LogLevel::Info, "test", "Third message");
        
        assert_eq!(cache.len(), 2);
        
        let entries = cache.get_entries();
        // First message should be dropped
        assert_eq!(entries[0].message, "Second message");
        assert_eq!(entries[1].message, "Third message");
    }

    #[test]
    fn test_log_cache_clear() {
        let cache = LogCache::new(5);
        
        cache.add_entry(LogLevel::Info, "test", "Message");
        assert_eq!(cache.len(), 1);
        
        cache.clear();
        assert_eq!(cache.len(), 0);
        assert!(cache.is_empty());
    }

    #[test]
    fn test_formatted_string_output() {
        let cache = LogCache::new(5);
        
        cache.add_entry(LogLevel::Info, "test", "Test message");
        cache.add_entry(LogLevel::Error, "app", "Error message");
        
        let formatted = cache.to_formatted_string();
        
        assert!(formatted.contains("INFO"));
        assert!(formatted.contains("ERROR"));
        assert!(formatted.contains("Test message"));
        assert!(formatted.contains("Error message"));
        assert!(formatted.contains("[test]"));
        assert!(formatted.contains("[app]"));
    }
}