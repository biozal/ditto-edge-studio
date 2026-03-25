# Ditto SDK & App Logging

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
| **App Logs** | Edge Studio's own CocoaLumberjack log files |
| **Imported** | Logs loaded from an external folder |

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

Type any text to filter entries by message content. The search is case-insensitive. Clear the field to see all entries again.

---

## Log Files on Disk

Ditto SDK logs are written to:
```
~/Library/Application Support/ditto_edge_studio/{name}-{databaseId}/database/logs/
```

- **Active file** (`.log`) — uncompressed, written as the SDK runs
- **Rotated files** (`.log.gz`) — gzip-compressed, immutable once closed
- Rotation: 1 MB or 24 h age; maximum 15 files (~15 MB total)

Edge Studio's own logs (CocoaLumberjack) are at:
```
~/Library/Logs/io.ditto.EdgeStudio/
```

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

Alternatively, use the **Export** button in the App Logs source to copy the CocoaLumberjack files to a chosen location.

---

## Clearing Logs

- **Clear** button in the Logging footer removes the currently shown source's entries:
  - *Ditto SDK*: clears live + historical in-memory entries (files remain on disk)
  - *App Logs*: deletes CocoaLumberjack log files from disk
  - *Imported*: removes the imported entries from the viewer
