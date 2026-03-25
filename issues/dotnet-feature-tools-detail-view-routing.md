# .NET: Missing Feature — Tools Detail View Routing

## Platform
.NET / Avalonia UI

## Feature Description
The Tools section in the sidebar lists multiple tools (Presence Viewer, Disk Usage, Permissions Health), but selecting any of them shows only a stub placeholder view ("Tools Detail View" text). The detail area needs to route to the appropriate tool-specific view based on the selected tool.

## SwiftUI Implementation Reference
- `SwiftUI/Edge Debug Helper/Views/MainStudioView.swift` — Routes sidebar selection to appropriate detail views
- Each tool has its own dedicated view that is swapped in when selected

## Current .NET Status
`ToolsDetailView.axaml` is a single stub view with hardcoded "Tools Detail View" text. `ToolsViewModel` populates a list of tool names as strings but there is no routing logic to swap detail views.

## Expected Behavior
- Selecting "Presence Viewer" in the Tools list shows the Presence Viewer
- Selecting "Disk Usage" shows the Disk Usage monitoring view
- Selecting "Permissions Health" shows the Permissions Health checker
- Navigation is smooth with no full-page reload
- Selected tool is visually highlighted in the list

## Key Implementation Notes
- This is a routing/navigation infrastructure issue that blocks ALL tools from working
- Recommend using a `ContentControl` with `DataTemplates` in Avalonia to swap views based on selected tool ViewModel type
- Each tool needs its own ViewModel (some already exist as stubs: `IndexesToolViewModel`, etc.)
- `ToolsDetailView` should be replaced with a dynamic content presenter
- Fix this first before implementing individual tool features, as it unblocks all other tool issues

## Acceptance Criteria
- [ ] Selecting each tool in the Tools list shows the corresponding detail view
- [ ] Presence Viewer tool routes to Presence Viewer content (even if "Coming Soon" initially)
- [ ] Disk Usage tool routes to Disk Usage content
- [ ] Permissions Health tool routes to Permissions Health content
- [ ] Selected tool is highlighted/active in the list
- [ ] Navigation state persists when switching between sidebar sections and returning to Tools
