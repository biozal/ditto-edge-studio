# Android: Missing Feature — Presence Viewer

## Platform
Android

## Feature Description
A visual mesh network graph showing all peers in the Ditto sync mesh — both directly and indirectly connected. Users can see the topology of the sync network, what transports each peer uses, and how the mesh is structured.

## SwiftUI Implementation Reference
- `SwiftUI/Edge Debug Helper/Views/Tools/PresenceViewerTab.swift` — Wrapper for DittoPresenceViewer with connection handling
- `SwiftUI/Edge Debug Helper/Views/MainStudioView.swift` — Presence tab in the Sync section
- Uses `DittoPresenceViewer` from the Ditto SDK

## Current Android Status
A "Presence" tab button exists in the Sync section UI, but it routes to a "Coming Soon" placeholder. No graph or peer topology visualization is implemented.

## Expected Behavior
- Display a live-updating visual graph of the Ditto mesh network
- Show all peers (direct and indirect) with connection transport types
- Update in real-time as peers connect and disconnect
- Each peer node shows: peer ID, platform, transport type(s)
- Visual distinction between directly connected and relay peers

## Key Implementation Notes
- The Ditto Android SDK may provide a `DittoPresenceViewer` composable or presence data API
- If no SDK component is available, build a graph view using Canvas/custom Composable
- Peer topology data is available from `ditto.presence.observe { graph -> ... }`
- The `graph.remotePeers` includes ALL mesh peers — filter to direct connections separately
- Already have peer list data in the Connected Peers section — presence viewer extends this with topology

## Acceptance Criteria
- [ ] "Coming Soon" placeholder replaced with live peer graph
- [ ] Graph updates in real-time as peers connect/disconnect
- [ ] Each peer node shows transport type (WebSocket, Bluetooth, P2P WiFi, etc.)
- [ ] Direct vs. indirect connections are visually distinguishable
- [ ] Works on both phone and tablet layouts
