# Ditto .NET SDK Migration Report: v4 → v5
## Edge Studio / Avalonia — Status

**Report Date:** 2026-03-26
**Auditor:** Claude (Senior .NET / Avalonia Developer)
**Codebase Path:** `dotnet/src/`
**SDK Migrated From:** Ditto 4.x (partially pre-migrated)
**SDK Migrated To:** Ditto 5.0.0-rc.1
**Skill File Under Review:** `plugins/ditto-v5-migration/skills/migrate-dotnet/SKILL.md`

---

## 1. Final Build Status

**macOS: BUILD SUCCEEDED**
```
Build succeeded.
0 Error(s)
2 Warning(s) — pre-existing Avalonia AVLN3001 warnings, unrelated to Ditto migration
```

---

## 2. Files Modified

| File | Change Type |
|------|-------------|
| `EdgeStudio.Shared/Data/DittoLogLevelHelper.cs` | Namespace fix |
| `EdgeStudio.Shared/Data/DittoManager.cs` | Namespace fix + removed deleted API |
| `EdgeStudio.Shared/Data/Repositories/SystemRepository.cs` | Namespace fix + property renames + removed property |
| `EdgeStudio.Shared/Data/Repositories/CollectionsRepository.cs` | Namespace fix |
| `EdgeStudio.Shared/Data/Repositories/SqliteSubscriptionRepository.cs` | Namespace fix |
| `EdgeStudio/Services/DittoLogCaptureService.cs` | Namespace fix |
| `EdgeStudio/ViewModels/LoggingViewModel.cs` | Namespace fix |

---

## 3. All V4 API Usages Found (Initial State)

| # | File | V4 Usage |
|---|------|----------|
| 1 | `DittoManager.cs` | `DittoSelectedApp.DisableSyncWithV3()` |
| 2 | `DittoManager.cs` | `DittoAuthenticationProvider.Development` (wrong namespace) |
| 3 | `DittoLogLevelHelper.cs` | `DittoLogLevel` / `DittoLogger` in `using DittoSDK;` |
| 4 | `SystemRepository.cs` | `DittoStoreObserver` in `using DittoSDK;` |
| 5 | `SystemRepository.cs` | `DittoPeer` / `DittoPresenceGraph` / `DittoConnection` in `using DittoSDK;` |
| 6 | `SystemRepository.cs` | `peer.PeerKeyString` property |
| 7 | `SystemRepository.cs` | `conn.PeerKeyString1` / `conn.PeerKeyString2` properties |
| 8 | `SystemRepository.cs` | `peer.Os` used as `string` (now `DittoPeerOS?`) |
| 9 | `SystemRepository.cs` | `conn.ApproximateDistanceInMeters` (removed) |
| 10 | `CollectionsRepository.cs` | `DittoStoreObserver` in `using DittoSDK;` |
| 11 | `SqliteSubscriptionRepository.cs` | `DittoSyncSubscription` in `using DittoSDK;` |
| 12 | `DittoLogCaptureService.cs` | `DittoLogger` / `DittoLogLevel` in `using DittoSDK;` |
| 13 | `LoggingViewModel.cs` | `DittoLogger` in `using DittoSDK;` |

---

## 4. Migrations Applied

### `DittoLogLevelHelper.cs`
- `using DittoSDK;` → `using DittoSDK.Logging;`

### `DittoManager.cs`
- Added `using DittoSDK.Auth;`
- Added `using DittoSDK.Logging;`
- Removed `DittoSelectedApp.DisableSyncWithV3();` call (removed in v5, no replacement)

### `SystemRepository.cs`
- Added `using DittoSDK.Store;`
- Added `using DittoSDK.Transport;`
- `presenceGraph.LocalPeer.PeerKeyString` → `presenceGraph.LocalPeer.PeerKey`
- `localPeer.PeerKeyString` → `localPeer.PeerKey`
- `localPeer.Os` (string) → `localPeer.Os?.ToString()` (DittoPeerOS? → string)
- `peer.PeerKeyString` → `peer.PeerKey` (in PublishConnectionCounts)
- `x.PeerKeyString == syncInfo.Id` → `x.PeerKey == syncInfo.Id`
- `remotePeer.PeerKeyString` empty check → `remotePeer.PeerKey` empty check
- `remotePeer.Os` → `remotePeer.Os?.ToString()`
- `conn.PeerKeyString1` → `conn.PeerKey1`
- `conn.PeerKeyString2` → `conn.PeerKey2`
- `conn.ApproximateDistanceInMeters` → `null` (property removed in v5)

### `CollectionsRepository.cs`
- Added `using DittoSDK.Store;`

### `SqliteSubscriptionRepository.cs`
- Added `using DittoSDK.Sync;`

### `DittoLogCaptureService.cs`
- `using DittoSDK;` → `using DittoSDK.Logging;`

### `LoggingViewModel.cs`
- `using DittoSDK;` → `using DittoSDK.Logging;`

---

## 5. Errors Encountered and Skill File Coverage

| Error | Skill File Coverage | Fix |
|-------|---------------------|-----|
| `DittoLogLevel`/`DittoLogger` not found — moved to `DittoSDK.Logging` | **NOT COVERED** | Add `using DittoSDK.Logging;` |
| `DittoSyncSubscription` not found — moved to `DittoSDK.Sync` | **NOT COVERED** | Add `using DittoSDK.Sync;` |
| `DittoPeer`/`DittoPresenceGraph` not found — moved to `DittoSDK.Transport` | **NOT COVERED** | Add `using DittoSDK.Transport;` |
| `DittoStoreObserver` not found — moved to `DittoSDK.Store` | **NOT COVERED** | Add `using DittoSDK.Store;` |
| `DittoAuthenticationProvider` not found — moved to `DittoSDK.Auth` | **PARTIALLY COVERED** — skill file says "use `DittoSDK.Auth`" but doesn't list `DittoAuthenticationProvider` explicitly | Add `using DittoSDK.Auth;` |
| `DittoPeer.PeerKeyString` → `PeerKey` (property rename) | **NOT COVERED** | Change to `.PeerKey` |
| `DittoConnection.PeerKeyString1/2` → `PeerKey1/2` (property rename) | **NOT COVERED** | Change to `.PeerKey1` / `.PeerKey2` |
| `DittoPeer.Os` type change — `string` → `DittoPeerOS?` | **NOT COVERED** | Use `.Os?.ToString()` |
| `DittoConnection.ApproximateDistanceInMeters` removed | **NOT COVERED** | Set to `null` |
| `DisableSyncWithV3()` removed | **CORRECTLY COVERED** | Removed call |

---

## 6. Skill File Accuracy Assessment

### What the Skill File Got Right

| Area | Status |
|------|--------|
| `Ditto.Sync.Start()` / `Sync.Stop()` rename | Correct — already used in codebase |
| `Ditto.OpenAsync(DittoConfig)` initialization | Correct — already in place |
| `DittoStoreObserver` type name (v5) | Correct name, wrong namespace assumption |
| `DittoSyncSubscription` type name (v5) | Correct name, wrong namespace assumption |
| `DittoStore.ExecuteAsync()` for DQL | Correct — already in place |
| Auth handler pattern with `LoginAsync()` | Correct — already correctly implemented |
| `DisableSyncWithV3()` listed as removed | Correct — caught and removed |
| `DittoDiskUsage.Exec()` → `.Item` property | Correct (not tested — not used in this codebase) |
| `Ditto.SiteId` → `Ditto.DeviceId` | Correct (not tested — not used in this codebase) |
| `DittoSDK.Exceptions` namespace | Likely correct (not tested) |

### What the Skill File Got Wrong or Missed

| Area | Issue |
|------|-------|
| Sub-namespace moves | **CRITICAL OMISSION** — types that were in root `DittoSDK` have moved to sub-namespaces. Not documented at all. |
| `DittoPeer.PeerKeyString` → `PeerKey` | **MISSING** — critical property rename affecting every peer-handling file |
| `DittoConnection.PeerKeyString1/2` → `PeerKey1/2` | **MISSING** — critical property renames affecting connection handling |
| `DittoPeer.Os` type change (`string` → `DittoPeerOS?`) | **MISSING** — type change causes CS0029, requires explicit `.ToString()` |
| `DittoConnection.ApproximateDistanceInMeters` removed | **MISSING** — breaking removal not documented |
| `DittoAuthenticationProvider` namespace not explicit | **INCOMPLETE** — `DittoSDK.Auth` mentioned but specific types not enumerated |

### Complete Namespace Migration Table (Missing from Skill File)

The most impactful gap is the lack of a namespace migration table. Every migrating project needs to add these `using` directives:

| Type | Old Namespace | New Namespace |
|------|---------------|---------------|
| `DittoLogLevel`, `DittoLogger` | `DittoSDK` | `DittoSDK.Logging` |
| `DittoStoreObserver`, `DittoQueryResultsChange`, `DittoQueryResultItem` | `DittoSDK` | `DittoSDK.Store` |
| `DittoSyncSubscription` | `DittoSDK` | `DittoSDK.Sync` |
| `DittoPeer`, `DittoPresenceGraph`, `DittoPresence`, `DittoConnection`, `DittoConnectionType` | `DittoSDK` | `DittoSDK.Transport` |
| `DittoAuthenticator`, `DittoAuthenticationProvider`, `DittoAuthenticationExpirationHandler` | `DittoSDK` | `DittoSDK.Auth` |
| `DittoException` | `DittoSDK` | `DittoSDK.Exceptions` |
| `DittoDiskUsageItem` | `DittoSDK` | `DittoSDK.DiskUsage` |

### Property Renames Missing from Skill File

| Type | V4 Property | V5 Property |
|------|-------------|-------------|
| `DittoPeer` | `PeerKeyString` | `PeerKey` |
| `DittoPeer` | `Os` (string) | `Os` (DittoPeerOS?) — type changed |
| `DittoConnection` | `PeerKeyString1` | `PeerKey1` |
| `DittoConnection` | `PeerKeyString2` | `PeerKey2` |
| `DittoConnection` | `ApproximateDistanceInMeters` | **REMOVED — no replacement** |

---

## 7. Verdict

### Is the Skill File Ready for Customers?

**NO — requires additions before it is production-ready.**

### Priority of Required Additions

**Must add (blockers — every project will hit these):**
1. Complete namespace migration table (7 sub-namespaces) — this is the #1 source of CS0246 errors
2. `DittoPeer.PeerKeyString` → `PeerKey` rename
3. `DittoConnection.PeerKeyString1/2` → `PeerKey1/2` renames
4. `DittoPeer.Os` type change from `string` to `DittoPeerOS?`
5. `DittoConnection.ApproximateDistanceInMeters` removal

**Should add (important for accuracy):**
6. Explicit list of types in `DittoSDK.Auth` namespace (not just "auth types")
7. Note that `DittoAuthenticationProvider` requires `using DittoSDK.Auth;`

### What the Migration Actually Required

The codebase had already adopted v5 DQL, `Ditto.OpenAsync`, and the new sync API in a prior partial migration pass. The remaining v4 usages were:
- **7 files** requiring new `using` directives for sub-namespace moves
- **5 property renames** on `DittoPeer` and `DittoConnection`
- **1 removed property** (`ApproximateDistanceInMeters`) set to `null`
- **1 removed method** (`DisableSyncWithV3`) deleted

The skill file would get a developer ~40% of the way to a clean build on this codebase. The namespace reorganization alone accounts for the majority of remaining errors. A developer following the skill file would be left with 9 unresolved compiler errors and no guidance on how to fix them.

---

## 8. Comparison with SwiftUI Migration

Both platform migrations shared similar patterns. The SwiftUI report (`migration-swiftui-status.md`) found that property renames on peer/connection types were the most common uncovered gap — this is identical in .NET:

| Gap | SwiftUI | .NET |
|-----|---------|------|
| Peer key property rename | `peerKeyString` → `peerKey` | `PeerKeyString` → `PeerKey` |
| Connection peer key renames | `peerKeyString1/2` → `peer1/2` | `PeerKeyString1/2` → `PeerKey1/2` |
| Distance removed | `approximateDistanceInMeters` removed | `ApproximateDistanceInMeters` removed |
| OS property type change | `osV2` → `os` (DittoPeerOS?) | `Os` type changed to `DittoPeerOS?` |
| Namespace reorganization | N/A (Swift doesn't have sub-namespaces) | Major gap — 7 sub-namespaces |

The .NET skill file has the additional critical gap of the sub-namespace reorganization, which has no Swift equivalent and affects nearly every file in a .NET Ditto project.
