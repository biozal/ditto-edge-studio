# Release Notes

## 1.0b5 — May 2026

### SwiftUI (macOS / iPadOS)

**Attachments (new)**
- Right-click any document row in **Raw** or **Table** view → **Add Attachment…** to pick a file from disk, name the field, and upload. The attachment token is written back onto the document.
- Right-click → **Delete Attachment…** opens a sheet listing every detected attachment field with toggles. Selected fields are nulled via `UPDATE <collection> SET <field> = null WHERE _id = '<docId>'`.
- **Attachment Viewer** section appears in the Inspector's Document Viewer for any selected row that has attachment fields. Shows size and download state per field; **Open** downloads and launches the attachment in the system default app.
- Progress overlay during upload/download; large files don't block the UI.

**Execution Profile (new)**
- New **Profile** tab next to **Raw** and **Table** captures Ditto's `~request_profile` envelope for the most recent `SELECT` you ran.
- **Card view** — every operator in the plan with stats badges (`in` / `out` document counts, `exec` / `recv` / `send` timings) and its attributes nested inside.
- **Plan view** — top-down tree of operator boxes connected by T-junction lines. An operator's box turns **orange** when it's the bottleneck (`exec` time exceeds 50% of total elapsed). Operators ≥ 5% of total elapsed get a percent-of-total badge.
- Times auto-scale to the most readable unit — milliseconds for ≥ 1 ms, microseconds for sub-ms, nanoseconds for sub-µs.
- Gated on the existing **Collect Metrics** Settings toggle. Profile capture only fires on Local-mode SELECTs; HTTP and non-SELECT statements never inject `PROFILE`.
- When the toggle is off, the Profile tab explains what's missing and offers a one-tap **Open Settings…** button.

**Welcome flow & first-run experience**
- New Welcome screen for users opening Edge Studio without any configured databases — links to the in-app User Guide and explains the built-in Quickstarts feature for pulling sample configurations.
- Empty-state titles, button colours and default tabs cleaned up for new-database first open.

**Query results**
- Full-row right-click context menu on both JSON and Table viewers, including a new **Copy _id** action alongside Copy JSON and the attachment actions above.
- Table viewer now fills its container, has visible row dividers, and anchors short result pages to the top (fixes the floating-table look on the last page of paginated results).

**Sync & lifecycle**
- Close → reopen no longer leaves the database file locked (cleanup teardown is now serialised: repositories first, manager second, presence observer explicitly released).
- Deleting a database configuration now removes all of its on-disk files.

**Logging**
- Log Export action restored to the Logging screen.

**Architecture**
- `MainStudioView.ViewModel` split into four sub-VMs (Phase 10a–10b).
- Protocol-based DI introduced so view models can be instantiated with mocked services in unit tests.

### .NET / Avalonia
- **Initial attachments support** added before the platform was archived: attachment viewer in the Document Viewer, Add Attachment context menu, and Delete Attachment dialog with field selection.
- **Archived going forward.** The `dotnet/` Avalonia implementation is no longer maintained. The Ditto Visual Studio Code extension and JetBrains IDE plugin replace it for the .NET community. The `dotnet/` tree remains in git history for reference only and is no longer included in the help-doc sync script.

### Android
- (No user-facing changes in this release; help docs synced from `docs/help/` source-of-truth.)

---

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
