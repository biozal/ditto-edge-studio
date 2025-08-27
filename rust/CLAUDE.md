# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Tauri-based desktop application for Ditto Edge Studio, built with:
- **Frontend**: React 19 + TypeScript + Vite
- **Backend**: Rust with Tauri v2
- **Purpose**: Cross-platform desktop client for managing Ditto databases (currently in initial development)

Note: This project will eventually include Edge Bot (codename Grimlock) CLI functionality for workflow automation.

## Development Commands

### Quick Start
```bash
# Install dependencies
npm install

# Run in development mode (starts both Vite and Tauri)
npm run tauri dev

# Build for production
npm run tauri build
```

### IMPORTANT: Build Validation
**ALWAYS run `npm run tauri build` after making changes to validate that the build works before reporting completion.** This ensures TypeScript compilation passes and the application bundles correctly. Changes should be tested in both development and production builds.

### Frontend Development
```bash
# Run Vite dev server only (without Tauri)
npm run dev

# Build frontend only
npm run build

# Preview production build
npm run preview

# Type checking
npx tsc --noEmit
```

### Backend Development
```bash
# Build Rust backend
cd src-tauri && cargo build

# Build release version
cd src-tauri && cargo build --release

# Run Rust tests
cd src-tauri && cargo test

# Run tests with single thread (recommended for env var tests)
cd src-tauri && cargo test -- --test-threads=1

# Check Rust code
cd src-tauri && cargo check

# Format Rust code
cd src-tauri && cargo fmt
```

### Rust Code Requirements

**MANDATORY**: All Rust code additions must follow these testing requirements:

1. **Trait-Based Design**: All implementations must be built around traits to enable dependency injection and mocking
2. **Comprehensive Testing**: Every function, method, and feature must have corresponding unit tests
3. **In-Memory Mocks**: Use in-memory mocks for all external dependencies (databases, file systems, network calls, etc.)
4. **Test Coverage**: Tests must prove the code works correctly including edge cases and error conditions

**Example Pattern**:
```rust
// Define trait for testability
pub trait DatabaseService {
    fn save_data(&self, data: &str) -> Result<(), String>;
    fn load_data(&self) -> Result<String, String>;
}

// Real implementation
pub struct DittoDatabaseService;
impl DatabaseService for DittoDatabaseService {
    fn save_data(&self, data: &str) -> Result<(), String> {
        // Real Ditto implementation
    }
    fn load_data(&self) -> Result<String, String> {
        // Real Ditto implementation
    }
}

// Mock for testing
pub struct MockDatabaseService {
    pub data: std::cell::RefCell<Option<String>>,
}
impl DatabaseService for MockDatabaseService {
    fn save_data(&self, data: &str) -> Result<(), String> {
        *self.data.borrow_mut() = Some(data.to_string());
        Ok(())
    }
    fn load_data(&self) -> Result<String, String> {
        self.data.borrow().clone().ok_or("No data".to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_save_and_load_data() {
        let mock = MockDatabaseService { 
            data: std::cell::RefCell::new(None) 
        };
        
        // Test save
        assert!(mock.save_data("test data").is_ok());
        
        // Test load
        let result = mock.load_data();
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), "test data");
    }
}
```

**No Exceptions**: Code that doesn't follow this pattern will not be accepted. This ensures maintainability, testability, and reliability of the codebase.

### Ditto-Specific Requirements

**CRITICAL MEMORY SAFETY RULES for Ditto Usage**:

1. **NEVER create pointers/references to the Ditto store**: Always access the store directly from the Ditto instance using `ditto.store()` on each call
2. **NEVER store store references**: Creating pointers to the store can cause memory leaks and crashes if the Ditto instance is removed from memory

**Example - CORRECT Usage**:
```rust
// ✅ CORRECT - Always access store directly
ditto.store().execute_v2("SELECT * FROM collection").await?;

// ✅ CORRECT - Each operation accesses store directly
ditto.store().collection("users").find_all().exec().await?;
ditto.store().collection("users").upsert(doc).await?;
```

**Example - INCORRECT Usage**:
```rust
// ❌ WRONG - Never create store pointers/references
let store = ditto.store();  // This can cause memory leaks!
store.execute_v2("SELECT * FROM collection").await?;

// ❌ WRONG - Never store store references in structs
struct BadExample {
    store: Store,  // This is dangerous!
}
```

**Enforcement**: Any code that creates pointers or references to Ditto stores will be rejected. This rule is non-negotiable for memory safety.

3. **ALWAYS use the Ditto Builder API**: Use `Ditto::builder()` for initialization, not `Ditto::open_sync()`

**Example - CORRECT Ditto Initialization**:
```rust
// ✅ CORRECT - Use the builder API
let ditto = Ditto::builder()
    .with_root(persistence_root)
    .with_identity(|ditto_root| {
        identity::OfflinePlayground::new(ditto_root, app_id)
    })?
    .build()?;
```

**Example - INCORRECT Ditto Initialization**:
```rust
// ❌ WRONG - Don't use open_sync directly
let config = DittoConfig::new(app_id, connect);
let ditto = Ditto::open_sync(config)?;  // Avoid this approach
```

### Ditto Observer v2 API

**Official Documentation**: [Store::register_observer_v2](https://software.ditto.live/rust/Ditto/4.12.0/x86_64-unknown-linux-gnu/docs/dittolive_ditto/store/struct.Store.html#method.register_observer_v2)

**Method Signature**:
```rust
pub fn register_observer_v2<Q, F>(
    &self, 
    query: Q, 
    on_change: F
) -> Result<Arc<StoreObserver>, DittoError>
```

**Key Behavior**:
- Configures Ditto to trigger the change handler whenever documents matching the query change in the local store
- The first invocation of the change handler happens after the method returns
- Observer callbacks are never called concurrently - one callback must complete before the next can be triggered
- The observer remains active until the `StoreObserver` handle is dropped, `observer.cancel()` is called, or the `Ditto` instance shuts down

**Example Usage**:
```rust
let _observer = ditto.store().register_observer_v2(
    "SELECT * FROM dittoappconfigs ORDER BY name",
    move |query_result| {
        let mut app_configs = Vec::new();
        
        // Parse query results using the iterator
        for item in query_result.iter() {
            match item.deserialize_value::<DittoAppConfig>() {
                Ok(config) => app_configs.push(config),
                Err(e) => log_error("observer", &format!("Failed to deserialize: {}", e)),
            }
        }
        
        // Emit to frontend or handle the data
        app.emit("app-configs-updated", &app_configs).unwrap();
    },
)?;
```

**QueryResult Methods** (from [QueryResult documentation](https://software.ditto.live/rust/Ditto/4.12.0/x86_64-unknown-linux-gnu/docs/dittolive_ditto/dql/struct.QueryResult.html)):
- `iter()`: Creates an iterator over `QueryResultItem`s for easy traversal
- `get_item(index)`: Retrieves a specific `QueryResultItem` by index
- `item_count()`: Returns the number of available items
- `mutated_document_ids()`: Returns document IDs that were mutated
- `commit_id()`: Provides the unique commit ID for tracking changes

**QueryResultItem Methods**:
- `deserialize_value::<T>()`: Deserialize the item's value into a specific type
- Recommended over manual JSON parsing for type safety and performance

### Tauri-Specific Commands
```bash
# Open Tauri dev tools
npm run tauri dev -- --devtools

# Build for specific platform
npm run tauri build -- --target x86_64-pc-windows-msvc
npm run tauri build -- --target x86_64-apple-darwin
npm run tauri build -- --target aarch64-apple-darwin

# Generate app icons
npm run tauri icon path/to/icon.png

# Update Tauri dependencies
npm run tauri update
```

## Project Structure

### Frontend (React/TypeScript)
```
src/
├── App.tsx           # Main React component
├── App.css           # Application styles
├── main.tsx          # React entry point
├── vite-env.d.ts     # Vite type definitions
├── assets/           # Static assets
├── components/       # Reusable UI components
├── hooks/            # Custom React hooks for business logic
│   └── useAppConfig.ts # App configuration management hook
├── models/           # TypeScript interfaces and data structures
│   └── DittoAppConfig.ts # Ditto app configuration model
├── providers/        # React context providers (ready for development)
└── services/         # API/service layer (ready for development)
```

### Backend (Rust/Tauri)
```
src-tauri/
├── src/
│   ├── main.rs                     # Entry point
│   ├── lib.rs                      # Core application logic and Tauri commands
│   ├── ditto_config.rs             # Ditto configuration and .env loading
│   ├── ditto_provider.rs           # Ditto instance providers and initialization
│   ├── ditto_app_config.rs         # DittoAppConfig model with serde
│   ├── logging.rs                  # Application logging system
│   └── repositories/               # Database operation repositories
│       ├── mod.rs                  # Repository module exports
│       └── ditto_local_cache_repository.rs # Local database CRUD operations
├── Cargo.toml          # Rust dependencies
├── tauri.conf.json     # Tauri configuration
├── build.rs            # Build script
├── capabilities/       # Tauri permissions
└── icons/              # Application icons
```

## Architecture Patterns

### React Frontend Architecture
**IMPORTANT**: All business logic must be separated from React components to ensure reusability and maintainability:

- **Components**: Pure UI components with minimal logic, focused on rendering and user interaction
- **Hooks**: Custom hooks for business logic, state management, and backend communication
- **Services**: Utility functions and API abstractions
- **Models**: TypeScript interfaces and data structures

#### Component Guidelines
- Components should NOT contain business logic like API calls, data transformation, or complex state management
- Use custom hooks to handle all backend communication
- Keep components focused on UI concerns only
- Pass data and callbacks via props

#### Hook Guidelines  
- Create custom hooks for all backend operations (CRUD, data fetching)
- Handle loading states, errors, and success states within hooks
- Return clean, typed interfaces for components to consume
- Example: `useAppConfig()` for app configuration management

#### Example Structure
```typescript
// ❌ Bad - Business logic in component
function MyComponent() {
  const [data, setData] = useState();
  const handleSave = async () => {
    try {
      await invoke('save_data', { data });
      // ... complex logic
    } catch (error) { /* ... */ }
  };
  return <div>{/* UI */}</div>;
}

// ✅ Good - Business logic in hook
function MyComponent() {
  const { data, saveData, isLoading, error } = useMyData();
  return <div>{/* Pure UI */}</div>;
}
```

### Backend Architecture

#### Repository Pattern
All database operations are organized in repositories under `src-tauri/src/repositories/`:
- `DittoLocalCacheRepository`: Handles all local database CRUD operations
- Repositories encapsulate DQL queries and database logic
- Clean separation between Tauri commands and database operations

#### Tauri Commands
Commands in `src-tauri/src/lib.rs` act as thin controllers:
```rust
#[tauri::command]
async fn add_ditto_app_config(state: State<'_, DittoState>, config: DittoAppConfig) -> Result<String, String> {
    let repository = DittoLocalCacheRepository::new(ditto);
    repository.add_app_config(config).await
}
```

### IPC Communication
Commands are defined in `src-tauri/src/lib.rs` and invoked from React:
```rust
// Backend (lib.rs)
#[tauri::command]
fn greet(name: &str) -> String {
    format!("Hello, {}!", name)
}
```

```typescript
// Frontend (useGreeting.ts hook)
export const useGreeting = () => {
  const greet = async (name: string) => {
    return await invoke("greet", { name });
  };
  return { greet };
};
```

### Adding New Commands
1. Define command in `src-tauri/src/lib.rs` with `#[tauri::command]`
2. Implement business logic in appropriate repository
3. Register in `tauri::generate_handler![]` macro
4. Create React hook for frontend communication
5. Use hook in components, never call `invoke()` directly in components

## Configuration

### Ditto Configuration (Environment Variables)

The application requires Ditto configuration through environment variables. Copy `.env.sample` to `.env` and fill in your values from the [Ditto Portal](https://portal.ditto.live):

```bash
# Copy the sample file
cp .env.sample .env
```

Required environment variables (exactly as in [Ditto quickstart](https://github.com/getditto/quickstart/tree/main/rust-tui)):
```bash
export DITTO_APP_ID=""              # Your Ditto App ID
export DITTO_PLAYGROUND_TOKEN=""    # Your playground token
export DITTO_AUTH_URL=""             # Authentication URL
export DITTO_WEBSOCKET_URL=""        # WebSocket URL for real-time sync
```

**Validation**: All 4 fields are required and cannot be empty. The application will return detailed error messages if any are missing or empty.

**Available Tauri Commands**:
- `get_ditto_config()` - Returns loaded and validated configuration
- `check_env_config()` - Test command to verify configuration loading

### Tauri Configuration (`src-tauri/tauri.conf.json`)
- **App ID**: `com.costoda.ditto-edge-studio`
- **Product Name**: `ditto-edge-studio`
- **Dev Server**: `http://localhost:1420`
- **Frontend Dist**: `../dist`
- **Window**: 800x600 default size

### Vite Configuration
- **Port**: 1420 (fixed for Tauri integration)
- **HMR Port**: 1421
- **Strict Port**: Enabled (fails if port unavailable)

### TypeScript Configuration
- **Target**: ES2020
- **Strict Mode**: Enabled
- **Module**: ESNext with bundler resolution
- **JSX**: react-jsx

## Permissions & Capabilities

Current permissions (`src-tauri/capabilities/default.json`):
- `core:default` - Core Tauri functionality
- `opener:default` - Open external links/files

To add new permissions:
1. Update `capabilities/default.json`
2. Install required Tauri plugins if needed
3. Update `Cargo.toml` dependencies

## Building & Distribution

### Development Build
```bash
npm run tauri dev
```
- Starts Vite on port 1420
- Launches Tauri window with dev tools available
- Hot module replacement enabled

### Production Build
```bash
npm run tauri build
```
- Creates optimized frontend bundle
- Compiles Rust in release mode
- Generates platform-specific installer in `src-tauri/target/release/bundle/`

### Platform-Specific Notes
- **macOS**: Requires code signing for distribution
- **Windows**: Generates MSI installer
- **Linux**: Creates AppImage and .deb packages

## Common Tasks

### Adding Tauri Plugins
```bash
# Example: Adding file system plugin
npm run tauri add fs
cd src-tauri && cargo add tauri-plugin-fs
```

### Debugging
1. Use browser DevTools in development mode
2. Add `console.log()` in TypeScript or `println!()` in Rust
3. Check Tauri console output for Rust errors

### State Management
For complex state, consider:
1. Frontend: React Context or state management library
2. Backend: Tauri state management with `tauri::State`
3. Persistent storage: Use Tauri plugins for file system or database access

## Future Development

Planned features for Edge Bot (Grimlock):
- Import/export data at intervals
- Workflow automation
- CLI interface alongside GUI
- Integration with Ditto SDK

## Current Implementation Status

✅ **Environment Configuration**: Complete Ditto .env setup with validation
- Environment variable loading using `dotenv` crate
- Comprehensive validation for all required fields
- Tauri commands for configuration access
- Full test coverage with proper validation

🚧 **In Development**: Integration with Ditto SDK for database operations