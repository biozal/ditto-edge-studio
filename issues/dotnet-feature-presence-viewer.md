# .NET: Missing Feature — Presence Viewer

## Platform
.NET / Avalonia UI

## Feature Description
A visual mesh network graph showing all connected peers in the Ditto sync mesh. Users can see which peers are directly or indirectly connected, what transports they are using, and the overall topology of the sync network.

## SwiftUI Implementation Reference
- `SwiftUI/Edge Debug Helper/Views/Tools/PresenceViewerTab.swift` — Wrapper for DittoPresenceViewer with connection handling
- `SwiftUI/Edge Debug Helper/Views/MainStudioView.swift` — Hosts the Presence Viewer in the Sync detail area (Peers tab)
- Uses `DittoPresenceViewer` from the Ditto SDK

## Current .NET Status
`ToolsDetailView.axaml` is a stub placeholder showing only "Coming Soon" text. No presence graph or peer topology visualization exists.

## Expected Behavior
- Display a live-updating visual graph of the Ditto mesh network
- Show all peers (direct and indirect) with their connection transport types
- Update in real-time as peers connect/disconnect
- Match the visual layout of the SwiftUI presence viewer

## Key Implementation Notes
- The Ditto .NET SDK provides presence/peer data via `ditto.Presence` or equivalent API
- The SwiftUI version wraps `DittoPresenceViewer` — the .NET SDK may have an equivalent component or the graph must be built manually
- Peer data is already partially available via `PeersListViewModel` and `SystemRepository` — the presence viewer extends this with topology visualization
- Should be accessible from the Sync section sidebar (Presence tab)

## Acceptance Criteria
- [ ] Presence Viewer tab in the Sync section shows a live peer graph
- [ ] Graph updates in real-time as peers connect and disconnect
- [ ] Each peer node shows transport type (WebSocket, Bluetooth, P2P WiFi, etc.)
- [ ] Direct vs. indirect connections are visually distinguishable
- [ ] "Coming Soon" placeholder is replaced with real content
