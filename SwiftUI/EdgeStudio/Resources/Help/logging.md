# Log Analyzer

The **Log Analyzer** captures Ditto SDK logs in real time and reads historical log files from disk so you can inspect past sessions, filter by level, and trace sync/transport/storage activity.

## What is Ditto SDK Logging?

The Ditto SDK writes structured log messages while it runs — covering sync, storage, queries, transport connections, and authentication. These logs are invaluable for debugging sync issues, diagnosing connectivity problems, and understanding database behaviour at runtime.

Edge Studio captures Ditto SDK logs in real-time and also reads historical log files from disk so you can inspect past sessions.

---

## Log Levels

The **SDK Log Level** setting controls the minimum severity of messages that Ditto will produce. Higher verbosity means more output but also more I/O overhead.

| Level | Use Case |
|-------|----------|
| **Error** | Only critical failures. Use in production to minimise overhead. |
| **Warning** | Errors + recoverable issues (e.g. missed retries). |
| **Info** *(default)* | Normal operational messages. Good for general debugging. |
| **Debug** | Detailed internal state. Use when reproducing a specific bug. |
| **Verbose** | Maximum detail including raw wire data. Very high volume. |

> **Note:** The log level is applied globally to `DittoLogger` when this database is activated. Because `DittoLogger` is a process-wide singleton, the setting affects all Ditto instances in the app.

You can change the log level in two places:
- **Database Editor** → Developer Options → SDK Log Level (persisted per database)
- **Logging view toolbar** → SDK Level picker (applies immediately to the active database)

---

## Using the Log Viewer

### Source Selector

| Source | What it shows |
|--------|---------------|
| **Ditto SDK** | Live callback stream + historical `.log` / `.log.gz` files |
| **App Logs** | Edge Studio's own log files — CocoaLumberjack logs on macOS / iPadOS; on Android, the app's own captured log entries (not CocoaLumberjack) |
| **Transport Conditions** | Transport health events from the SDK (BLE, TCP, mDNS, AWDL) — permission denials, disabled radios, listener failures |
| **Connection Requests** | Incoming peer connection requests (peer key, connection type, metadata) |
| **Imported** | Logs loaded from an external folder *(macOS / iPadOS only)* |

### Level Chips

Click the coloured chips (ERR, WARN, INFO, DBG, VERB) to toggle which severity levels are visible. Multiple levels can be active at the same time.

### Component Filter *(Ditto SDK / Imported only)*

Filters entries by the SDK subsystem that produced them:

| Component | SDK Target |
|-----------|-----------|
| **Sync** | `ditto::sync` — replication engine, subscription processing |
| **Store** | `ditto::store` — document storage, indexes |
| **Query** | `ditto::query` — DQL execution and planning |
| **Observer** | `ditto::observer` — change listeners |
| **Transport** | `ditto::transport` — BLE, LAN, AWDL, WebSocket |
| **Auth** | `ditto::auth` — identity and token refresh |

### Search

Type any text to filter entries by message content. The search is case-insensitive. Entries' **user tags** (see below) are also included in the search. Clear the field to see all entries again.

### Date Range

Enable the **Date range** toggle to restrict entries between two dates (full-day bounds on Android).

### Export

The footer's **Export** button writes the current source's captured entries to a file. On Android, the system save sheet opens a text file anywhere you choose; on macOS / iPadOS a folder picker copies the raw `.log` / `.log.gz` files.

---

## Log Patterns (Problem Matching)

The Log Analyzer scans every entry against a catalog of regex patterns and surfaces matches as **problems** — known trouble signatures with a severity, a hit count, and a recommendation. When anything matches, a clickable strip appears above the log list ("N problems matched on M log lines"); tap a hit to jump to it in the table.

Open the manager from the toolbar (**Patterns** / slider icon).

### Pattern schema

| Field | Meaning |
|-------|---------|
| **Key** | Unique identifier (e.g. `deadlock_critical`). Cannot collide with a bundled key. |
| **Pattern** | Regular expression, matched **case-insensitively against the message body** of each entry. |
| **Severity** | 1 (info) – 5 (critical); controls chip color and sort order. |
| **Recommendation** | Required. Shown next to the pattern in the Problems list. |
| **Level filter** | Optional **exact** log level match (`error`, `warning`, `info`, `debug`, `verbose`) — an exact equality, not "at least", so tiered patterns (e.g. deadlock at warn vs error) stay mutually exclusive. |
| **Component filter** | Optional regex (case-sensitive) against the entry's component name (`Sync`, `Store`, `Query`, `Observer`, `Transport`, `Auth`). |
| **User tag** | Optional label attached to every line the pattern matches — shown as a chip on the row and included in search. |

Safety guards for user patterns: maximum 512 characters, and nested quantifiers such as `(a+)+` are rejected (they can backtrack exponentially).

The editor validates the regex as you type and includes a **test line** field: paste a log line to see a live ✓/✗ match result.

### Where patterns live

- **Bundled** (read-only): a built-in catalog of known Ditto problem signatures (deadlocks, query size limits, certificate expiry, authentication failures, incomplete connections, OOM, crash signals).
- **User patterns**: persisted between launches in `user_patterns.json` under the app support / private storage directory — macOS/iPadOS: `~/Library/Application Support/ditto_edge_studio/log-analyzer/`; Android: `<filesDir>/log-analyzer/`. The JSON format matches the bundled catalog and the VS Code extension, so a patterns file can be shared across Edge Studio editions by hand.

> **Note:** Only the newest 5,000 entries of the active source are scanned, and the scan is throttled to keep hot log streams from janking the UI.

---

## Log Files on Disk

Ditto SDK logs are written to (macOS / iPadOS):
```
~/Library/Application Support/ditto_edge_studio/{name}-{databaseId}/database/logs/
```

On Android, the Ditto persistence directory lives under the app's private storage (`<filesDir>/ditto/…`). The footer's **Export** button writes the currently visible source's entries to a text file via the system save sheet — no `adb` needed for the captured view; raw `.log`/`.log.gz` files still require `adb` on debuggable builds.

- **Active file** (`.log`) — uncompressed, written as the SDK runs
- **Rotated files** (`.log.gz`) — gzip-compressed, immutable once closed
- Rotation: 1 MB or 24 h age; maximum 15 files (~15 MB total)

Edge Studio's own logs (CocoaLumberjack, macOS / iPadOS only) are at:
```
~/Library/Logs/io.ditto.EdgeStudio/
```

On Android, Edge Studio's own app logs are stored in the app's private storage (`<filesDir>/app_logs/`) instead.

---

## Importing Logs from Other Devices *(macOS)*

To examine logs from an Android device, another Mac, or a server:

1. Copy the device's `logs/` directory to your Mac (via ADB, SSH, file transfer, etc.)
2. In the Logging view, click **Import External Logs…**
3. Select the folder containing `.log` / `.log.gz` files
4. Switch the source selector to **Imported**

Both Ditto SDK JSON Lines format and CocoaLumberjack plain-text format are auto-detected.

---

## Exporting Logs for Bug Reports

To share logs with the Ditto team:
1. Locate the logs directory shown above in Finder
2. Compress the `logs/` folder as a ZIP
3. Attach to the GitHub issue at https://github.com/getditto/ditto/issues

Alternatively, on macOS / iPadOS, use the **Export** button in the App Logs source to copy the CocoaLumberjack files to a chosen location. On Android, use the same footer **Export** button to save the currently visible source (Ditto SDK, App Logs, Transport Conditions, or Connection Requests) as a text file; raw on-disk log files still require `adb` on debuggable builds.

---

## Clearing Logs

- **Clear** button in the Logging footer removes the currently shown source's entries:
  - *Ditto SDK*: clears live + historical in-memory entries (files remain on disk)
  - *App Logs*: deletes the app log files from disk (CocoaLumberjack files on macOS / iPadOS; the app's own log files on Android)
  - *Imported*: removes the imported entries from the viewer
