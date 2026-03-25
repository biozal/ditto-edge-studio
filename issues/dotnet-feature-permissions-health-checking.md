# .NET: Missing Feature — Permissions Health Checking

## Platform
.NET / Avalonia UI

## Feature Description
A tool that checks and displays the status of system permissions required for Ditto sync transports — specifically Bluetooth and local network/Wi-Fi permissions. Users can see at a glance which permissions are granted, denied, or missing, and understand what impact that has on sync functionality.

## SwiftUI Implementation Reference
- `SwiftUI/Edge Debug Helper/Views/Tools/` — Permissions Health tool view
- Uses platform APIs to query Bluetooth and network permission status
- Accessible from the Tools section of the app

## Current .NET Status
`ToolsViewModel` lists "Permissions Health" as a navigation item, but no implementation exists. `ToolsDetailView.axaml` is a stub. No permission-checking logic is present anywhere in the codebase.

## Expected Behavior
- List all permissions relevant to Ditto sync (Bluetooth, Local Network, etc.)
- Show current status for each permission: Granted / Denied / Not Determined
- Indicate which sync transports are affected by missing permissions
- Provide guidance or a button to open system settings to grant permissions
- Update status when permissions change

## Key Implementation Notes
- On Windows (primary .NET platform): check Bluetooth adapter availability and network adapter status
- The .NET/Windows platform may have different permission concepts than macOS/iOS — adapt accordingly
- If running on Linux or other platforms, surface what is applicable
- `ToolsDetailView` needs to route to the correct detail view based on selected tool

## Acceptance Criteria
- [ ] Permissions Health tool is accessible from the Tools section
- [ ] Lists all sync-relevant permissions with current status
- [ ] Shows clear visual indicator (green/red/yellow) per permission
- [ ] Explains impact on sync for each missing permission
- [ ] "Tools Detail View" stub is replaced with real content
