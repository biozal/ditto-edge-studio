# .NET: Missing Feature — Disk Usage Monitoring

## Platform
.NET / Avalonia UI

## Feature Description
A dedicated tool that shows how much disk space the Ditto database is consuming. Users can see total database size, per-collection storage breakdown, and monitor storage growth over time.

## SwiftUI Implementation Reference
- `SwiftUI/Edge Debug Helper/Views/Tools/` — Disk Usage tool view
- `SwiftUI/Edge Debug Helper/Data/Repositories/SystemRepository.swift` — Tracks disk usage metrics
- Accessible from the Tools section of the app

## Current .NET Status
`ToolsViewModel` lists "Disk Usage" as a navigation item, but `ToolsDetailView.axaml` is a stub showing only "Tools Detail View" text. `AppMetricsViewModel` tracks `StorageBytes` as part of system metrics but there is no dedicated Disk Usage tool UI that surfaces this clearly to the user.

## Expected Behavior
- Show total Ditto database size in human-readable format (KB, MB, GB)
- Show per-collection storage breakdown if available from the SDK
- Live-updating as data changes
- Accessible from the Tools section in the sidebar

## Key Implementation Notes
- `AppMetricsViewModel` already reads `StorageBytes` from the Ditto SDK — this data can be reused
- The dedicated Disk Usage view should present this data in a more prominent, user-friendly way
- `ToolsDetailView` needs to route to the correct tool detail based on the selected tool item
- May need to query `ditto.DiskUsage` or equivalent SDK property

## Acceptance Criteria
- [ ] Disk Usage tool is accessible from the Tools section
- [ ] Shows total database size in human-readable format
- [ ] Data updates when navigating to the view
- [ ] "Tools Detail View" stub is replaced with real content
- [ ] Handles case where disk usage data is unavailable gracefully
