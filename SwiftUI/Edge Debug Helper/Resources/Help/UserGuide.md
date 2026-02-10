# Edge Debug Helper - User Guide

Welcome to Edge Debug Helper, your comprehensive tool for managing Ditto databases.

## Getting Started

### Adding Your First Database

1. Click the **Add Database** button on the main screen
2. Select your authentication mode:
   - **Online Playground**: For cloud-connected apps
   - **Offline Playground**: Local-only development
   - **Shared Key**: For apps using shared key authentication
3. Fill in required credentials
4. Click **Save**

### Connecting to a Database

Select any database card from the list to open the main studio view.

## Features

### Collections Tab

Query and manage your Ditto collections using DQL (Ditto Query Language).

Learn more at [Ditto Documentation](https://docs.ditto.live)

### Subscriptions Tab

Monitor real-time sync activity with three views:
- **Peers List**: Connected devices and transport status
- **Presence Viewer**: Visual mesh network representation
- **Settings**: Sync configuration options

### Observer Tab

Track real-time document changes with event filtering and diffing.

## Keyboard Shortcuts

- **⌘?** - Open Ditto Documentation
- **⌘H** - User Guide (this help)
- **⌘⇧D** - Font Debug Window

## Troubleshooting

### Connection Issues

Check your authentication credentials and network connectivity. Ensure:
- App ID is correct (36 characters)
- Auth token is valid (if using online playground)
- Network allows outbound connections

### Sync Not Working

Verify sync is enabled in the Subscriptions tab settings panel.

---

*For more information, visit [docs.ditto.live](https://docs.ditto.live)*
