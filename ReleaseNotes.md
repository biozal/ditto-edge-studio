# Release Notes

## 1.0b3 — March 2026

### SwiftUI (macOS / iPadOS)

**Window & Layout**
- Fixed window clipping on MacBook Pro 14" M4 and other laptops with smaller displays. The minimum window size was reduced from 1400×820 to 960×680 so the app no longer overflows the screen when maximized.
- Fixed window position restore — saved frames from external monitors are now clamped within the visible area of the best available screen instead of restoring partially off-screen.

**Peers List**
- Peer ID and network address text on peer cards no longer truncates. Both fields now wrap so the full value is always readable regardless of card width.
- Double-click a peer ID or network address on macOS to copy it to the clipboard. The text briefly turns green to confirm the copy.
- Peer cards grid minimum column width reduced from 340 to 260 pt so more cards are visible on smaller Mac displays.
- Scroll content in the Peers List now clears the floating bottom toolbar so the last card is never hidden.

**Presence Viewer**
- **Direct Connected toggle** — a new switch in the lower-right corner (on by default) filters the graph to show only peers directly connected to this device. Turn it off to see the full mesh of all peers connected to all peers.
- Fixed connection lines drawing through unrelated nodes. Ring-1 peers that are directly connected to each other are now placed adjacent on the circle using a greedy path algorithm, keeping their connection chord short.
- Peer-to-peer connection lines (ring-to-ring chords) now arc outward from the cluster instead of cutting through unrelated nodes near the center.
- Zoom controls and connection legend moved up to clear the floating bottom toolbar overlay.
- Removed Test Mode. The feature has been stable and is no longer needed.

**Android**
- Disk usage screen added.
- Peer list cards updated to better match the SwiftUI layout.
- Query editor added.
- Multiple tablet UI fixes.

**.NET / Avalonia**
- Initial .NET check-in with query editor (multiple fixes), logging screen, and Peer List aligned to SwiftUI.

---

## 1.0b2 — Previous Release

See git tag `v1.0b2` for the baseline.
