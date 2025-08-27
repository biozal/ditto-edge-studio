# Ditto Edge Studio - Tauri Application

A cross-platform desktop application for managing Ditto databases, built with Tauri, React, and TypeScript.

## Setup

### 1. Configure Ditto Environment

Copy the sample environment file and configure it with your Ditto credentials:

```bash
cp .env.sample .env
```

Edit `.env` and add your Ditto configuration:
- `DITTO_APP_ID`: Your Ditto App ID from the Ditto Portal (required)
- `DITTO_AUTH_TOKEN`: Your authentication token
- `DITTO_AUTH_URL`: Your authentication URL
- Other optional settings for transports and logging

### 2. Install Dependencies

```bash
npm install
```

### 3. Run the Application

```bash
# Development mode with hot reload
npm run tauri dev

# Build for production
npm run tauri build
```

## Environment Configuration

The application uses environment variables for Ditto configuration. See `.env.sample` for all available options:

- **Authentication**: Configure online/offline mode and authentication endpoints
- **Transports**: Enable/disable Bluetooth, LAN, AWDL, and cloud sync
- **Storage**: Set custom database storage path
- **Logging**: Configure log levels for debugging

## Permissions

On macOS, the application requires the following permissions for Ditto P2P functionality:
- Bluetooth access for device-to-device sync
- Local network access for LAN sync
- Bonjour/AWDL for Apple device discovery

These permissions are configured in `entitlements.plist` and will be requested when needed.

## Development

### Available Commands

```bash
# Frontend only development
npm run dev

# Build frontend only
npm run build

# Run Tauri in development mode
npm run tauri dev

# Build Tauri application
npm run tauri build

# Build for specific platform
npm run tauri build -- --target x86_64-apple-darwin
```

### Testing Ditto Connection

The application includes test commands to verify Ditto SDK integration:
- `get_ditto_config`: Returns current configuration from environment
- `test_ditto_connection`: Tests connection with current settings
- `check_ditto_sdk`: Verifies SDK is properly installed

## Recommended IDE Setup

- [VS Code](https://code.visualstudio.com/) + [Tauri](https://marketplace.visualstudio.com/items?itemName=tauri-apps.tauri-vscode) + [rust-analyzer](https://marketplace.visualstudio.com/items?itemName=rust-lang.rust-analyzer)
