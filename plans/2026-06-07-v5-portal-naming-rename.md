# v5 Portal Naming Rename (2026-06-07)

Align database-config terminology with the Ditto v5 portal. **Chosen strategy:
rename user-facing layer only; keep internal SQLite column names** (no schema
migration, no data loss). Bridge old columns → new model names at the repository.

## Name mapping (portal v5)
| Concept | Old (code) | New (v5) |
|---|---|---|
| mode | `AuthMode.server` ("server") | `.development` ("development") |
| mode | `AuthMode.smallPeersOnly` ("smallpeersonly") | `.smallPeerOnly` ("smallPeerOnly") |
| dev token | `token` | `developmentToken` |
| url | `authUrl` | `url` |
| db id | `databaseId` | `databaseId` (already correct) |

## Layers
- **Model `DittoConfigForDatabase`**: rename `authUrl`→`url`, `token`→`developmentToken`
  (property, init, `new()`, CodingKeys, encode/decode). Add `decodeIfPresent`
  fallback to legacy keys (`authUrl`,`token`) so old QR/JSON/dittoConfig.plist
  still import.
- **`AuthMode`**: rename cases + raw values + displayName; add a legacy-tolerant
  parser mapping old stored strings ("server"→.development,
  "smallpeersonly"→.smallPeerOnly, plus old playground strings).
- **SQLCipherService**: UNCHANGED. SQL columns stay `authUrl`/`token`;
  `DatabaseConfigRow` keeps those field names (mirror of columns).
- **DatabaseRepository**: bridge — `row.authUrl`→`config.url`,
  `row.token`→`config.developmentToken`; map mode String↔AuthMode via the
  legacy-tolerant parser so old stored `mode` values still load.
- **DittoManager**: `.server`→`.development`, `.smallPeersOnly`→`.smallPeerOnly`,
  `appConfig.authUrl`→`.url`, `appConfig.token`→`.developmentToken`.
- **DatabaseEditorView** + ViewModel: rename props/bindings/labels; mode picker.
- **ContentView, QuickstartDownloadService, KeychainService, MCPToolHandlers**:
  field-ref renames.
- **DittoAppConfigLoader + AppState testDatabaseConfig parser**: read new plist
  keys (`databaseId`, `developmentToken`, `url`, mode `development`/`smallPeerOnly`)
  with fallback to legacy keys.
- **dittoConfig.plist + testDatabaseConfig.plist.example**: rewrite to v5 keys/modes.
- **Tests + fixtures (~19 files)**: update to new API + raw values (Phase 2).

## Verify
macOS + iOS app builds clean (0 warnings) → build-for-testing → all unit tests pass
→ confirm legacy-decode fallbacks with a round-trip test.
