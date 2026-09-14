# Edge Studio v1.0 Beta 5

**Android is now available for the first time.** This release ships both a macOS
app and a sideloadable Android APK.

## Downloads

| Platform | Asset | Requirements |
|---|---|---|
| macOS | `Ditto Edge Studio 1.0b5.dmg` | macOS 26.0+, **Apple Silicon** |
| Android | `EdgeStudio-1.0b5-arm64.apk` | Android 9 (API 28)+, 64-bit ARM |

### Installing on macOS

Open the DMG and drag **Ditto Edge Studio** to Applications. The app is signed
with a Developer ID certificate and notarized by Apple, so it opens normally —
no Gatekeeper workaround needed.

> **Apple Silicon only.** There is no Intel build. The Ditto SDK ships an
> arm64-only framework for macOS, so an Intel binary isn't possible.

### Installing on Android (sideloading)

The APK is distributed directly rather than through the Play Store, so you'll
need to allow installs from wherever you downloaded it:

1. Download `EdgeStudio-1.0b5-arm64.apk` to your device.
2. Open it. Android will prompt to allow installs from your browser or file
   manager — **Settings → Install unknown apps** → enable for that app.
3. Return to the download and tap **Install**.

The APK is signed with our own release key. Android will show it as coming from
an unverified developer; that's expected for a direct download and doesn't
indicate a problem.

> **Beta note:** because this is the first Android release, updating from a
> future version will work normally — but if you ever installed a self-built
> debug APK, uninstall it first, as the signing keys differ.

---

## What's New

### Attachments (SwiftUI & Android)

Add, view, and delete document attachments directly from query results.

- **macOS/iPadOS** — right-click any row in **Raw** or **Table** view →
  **Add Attachment…** to pick a file and name the field, or
  **Delete Attachment…** for a sheet listing every detected attachment field
  with toggles. An **Attachment Viewer** section appears in the Inspector's
  Document Viewer showing size and download state per field; **Open** downloads
  and launches the file in the system default app.
- **Android** — long-press a row for Add/Delete; attachments render inline in
  the JSON inspector with image preview.
- Uploads and downloads show a progress overlay and never block the UI.

### Execution Profile (SwiftUI & Android)

A new **Profile** tab alongside **Raw** and **Table** captures Ditto's
`~request_profile` envelope for the most recent `SELECT`.

- **Card view** — every operator in the plan with stats badges (`in`/`out`
  document counts, `exec`/`recv`/`send` timings) and attributes nested inside.
- **Plan view** — a top-down tree of operator boxes joined by T-junction lines.
  An operator turns **orange** when it's the bottleneck (`exec` exceeds 50% of
  total elapsed); anything ≥ 5% of total gets a percent badge.
- Times auto-scale to the most readable unit (ms / µs / ns).
- Gated on the **Collect Metrics** setting. Capture only fires on Local-mode
  SELECTs — HTTP and non-SELECT statements never inject `PROFILE`.
- Android ships the Card view with visual parity to the SwiftUI plan viewer.

### Per-database Advanced Configuration (SwiftUI & Android)

Each database gets its own **Advanced Configuration**, reachable by editing the
database card: startup settings applied via `ALTER SYSTEM` before sync starts,
plus per-collection **sync scopes** with read-back verification.

### Indexes (SwiftUI)

- **Composite indexes** with per-field **ASC/DESC** sort direction via a new
  **Add Index** sheet. The sidebar shows sort direction on composite fields
  (e.g. `createdAt ↓`).
- New `list_indexes` MCP tool for auditing index coverage across collections.

### MCP server (SwiftUI)

- **Hardened** — the server now binds to the loopback interface only and the
  CORS headers were removed. It is no longer reachable from other machines or
  from browser pages.
- Three new tools (15 total): `list_indexes`, `get_app_logs`, and
  `get_ditto_logs` (structured SDK log entries with level/substring filters).

### Welcome flow & first-run (SwiftUI)

A new Welcome screen greets users with no configured databases, linking to the
in-app User Guide and explaining the Quickstarts feature for pulling sample
configurations. Empty-state titles, button colours, and default tabs were
cleaned up for first open.

### Query results (SwiftUI)

- Full-row right-click context menu on both JSON and Table viewers, including a
  new **Copy _id** action.
- The Table viewer now fills its container, has visible row dividers, and
  anchors short result pages to the top.

### Android shell

The studio shell was rebuilt on **Navigation 3 scenes**; Query Metrics,
Logging, App Metrics, Disk Usage, and Observers all migrated onto it. The Query
Metrics list moved into the Data Panel.

### Ditto SDK

Upgraded to **Ditto SDK 5.1** on both platforms.

---

## Bug Fixes

### Sync & lifecycle
- Close → reopen no longer leaves the database file locked. Cleanup teardown is
  serialised: repositories first, manager second, presence observer explicitly
  released.
- Deleting a database configuration now removes all of its on-disk files, and
  every delete path sits behind a single confirmation dialog.
- Fixed several **observer crashes** — activating an observer no longer crashes
  on documents `jsonData()` can't serialise, result items are dematerialised in
  the live-query callback, and observers are cancelled on reset.

### Query & history
- **Query Metrics** fixes, including a guard against cross-database write
  races: history saves completing after a database switch carry the original
  database id and are refused when the session no longer matches.
- **Attachment delete is now injection-safe** — the document id is passed as a
  bound DQL argument (`:docId`) rather than interpolated, so a crafted `_id`
  from a synced document can't smuggle DQL.
- Fixed the app version string (now correctly reports 1.0b5).

### Logging
- Log Export action restored to the Logging screen.

---

## Technical Improvements

- `MainStudioView.ViewModel` split into four sub-view-models.
- Protocol-based DI so view models can be instantiated with mocked services in
  unit tests.
- Android release builds are now signed and restricted to `arm64-v8a`, cutting
  the APK from 316 MB to ~131 MB.

---

**Full Changelog**: `v1.0b4...v1.0b5`
