# Ditto Swift SDK Migration Report: v4 → v5
## SwiftUI / Edge Studio — Status

**Report Date:** 2026-03-25
**Auditor:** Claude (Senior Swift Developer)
**Codebase Path:** `SwiftUI/EdgeStudio/`
**SDK Migrated From:** Ditto 4.x (partially pre-migrated)
**SDK Migrated To:** Ditto 5.0.0-rc.1
**Skill File Under Review:** `Ditto Swift SDK: v4.14 → v5.0 Migration Reference`

---

## 1. Final Build Status

**macOS: BUILD SUCCEEDED**
**iOS (iPad Pro 13-inch M5 Simulator): BUILD SUCCEEDED**

Both platforms compile cleanly against Ditto SDK 5.0.0-rc.1 after the fixes applied in this session.

---

## 2. All Errors Encountered (Initial Build)

Running the initial build against 5.0.0-rc.1 produced the following compiler errors (unique, sorted):

| # | File | Line | Error Message |
|---|------|------|---------------|
| 1 | `StorageRepository.swift` | 17 | `value of type 'DittoDiskUsage' has no member 'exec'` |
| 2 | `StorageRepository.swift` | 37 | `cannot find type 'DiskUsageItem' in scope` |
| 3 | `SystemRepository.swift` | 55 | `type 'DittoPeer' does not conform to protocol 'PeerProtocol'` |
| 4 | `SystemRepository.swift` | 55 | `type 'DittoConnection' does not conform to protocol 'ConnectionProtocol'` |
| 5 | `SystemRepository.swift` | 62 | `value of type 'DittoPeer' has no member 'osV2'` |
| 6 | `SystemRepository.swift` | 85 | `value of type 'DittoPeer' has no member 'peerKeyString'` |
| 7 | `SystemRepository.swift` | 141 | `trailing closure passed to parameter of type 'Predicate<DittoConnection>' that does not accept a closure` |
| 8 | `SystemRepository.swift` | 213 | `value of type 'DittoPeer' has no member 'peerKeyString'` |
| 9 | `SystemRepository.swift` | 465 | `value of type 'DittoPeer' has no member 'peerKeyString'` |
| 10 | `SystemRepository.swift` | 558 | `value of type 'DittoPeer' has no member 'peerKeyString'` |
| 11 | `SystemRepository.swift` | 590 | `failed to produce diagnostic for expression; please submit a bug report` (cascading error, resolved when #10 was fixed) |
| 12 | `DittoManager.swift` | 122 | `actor-isolated property 'appState' cannot be accessed from outside of the actor` |

All 12 errors were resolved. The `PresenceProtocols.swift` protocol conformance fix (error #3 and #4) also resolved errors #5, #6, #8, #9, #10 because the bridge approach made the old property names available on the concrete types.

---

## 3. Fix Applied for Each Error

### Fix 1 & 2 — `StorageRepository.swift`: Disk Usage API

**File:** `/Users/labeaaa/Developer/ditto/ditto-edge-studio/SwiftUI/EdgeStudio/Data/Repositories/StorageRepository.swift`

**Error 1:** `value of type 'DittoDiskUsage' has no member 'exec'`
**Error 2:** `cannot find type 'DiskUsageItem' in scope`

**Before:**
```swift
let root = await Task.detached(priority: .utility) {
    ditto.diskUsage.exec
}.value

private static func flattenTree(_ item: DiskUsageItem) -> [(path: String, sizeInBytes: Int)] {
```

**After:**
```swift
let root = await Task.detached(priority: .utility) {
    ditto.diskUsage.item
}.value

private static func flattenTree(_ item: DittoDiskUsageItem) -> [(path: String, sizeInBytes: Int)] {
```

**Source:** Skill file (both renames are explicitly listed).

**Additional finding:** The `DittoDiskUsageItem` property names `.path`, `.sizeInBytes`, and `.childItems` did NOT change in v5. The skill file was correct that `exec` → `item` and that `DiskUsageItem` → `DittoDiskUsageItem`, but was silent on the property names. Fortunately they remained stable.

---

### Fix 3 & 4 — `PresenceProtocols.swift`: DittoPeer and DittoConnection Protocol Conformance

**File:** `/Users/labeaaa/Developer/ditto/ditto-edge-studio/SwiftUI/EdgeStudio/Components/PresenceViewer/PresenceProtocols.swift`

**Errors:**
- `type 'DittoPeer' does not conform to protocol 'PeerProtocol'`
- `type 'DittoConnection' does not conform to protocol 'ConnectionProtocol'`

**Root cause:** In v5:
- `DittoPeer.peerKeyString` was renamed to `DittoPeer.peerKey`
- `DittoPeer.isConnectedToDittoCloud` was renamed to `DittoPeer.isConnectedToDittoServer`
- `DittoPeer.osV2` was renamed to `DittoPeer.os`
- `DittoConnection.peerKeyString1` was renamed to `DittoConnection.peer1`
- `DittoConnection.peerKeyString2` was renamed to `DittoConnection.peer2`
- `DittoConnection.approximateDistanceInMeters` was **removed entirely** (no replacement)

**Strategy chosen:** Rather than renaming all call sites (20+ locations) to the new v5 property names, we added bridge computed properties in the `DittoPeer` and `DittoConnection` Swift extensions. This is the most maintainable approach because `PresenceProtocols.swift` is an internal abstraction layer specifically designed to decouple the app from the SDK's concrete types.

The bridge approach also preserves `MockPeer` and `MockConnection` test types without requiring their property names to change.

**Key change — `DittoPeer` extension:**
```swift
// v5 bridge: peerKey → peerKeyString, isConnectedToDittoServer → isConnectedToDittoCloud
extension DittoPeer: PeerProtocol {
    var peerKeyString: String { peerKey }
    var isConnectedToDittoCloud: Bool { isConnectedToDittoServer }
    var connectionProtocols: [any ConnectionProtocol] {
        connections.map { $0 as ConnectionProtocol }
    }
}
```

**Key change — `DittoConnection` extension:**
```swift
// v5 bridge: peer1 → peerKeyString1, peer2 → peerKeyString2
extension DittoConnection: ConnectionProtocol {
    var peerKeyString1: String { peer1 }
    var peerKeyString2: String { peer2 }
}
```

**`ConnectionProtocol` change — `approximateDistanceInMeters` removed:**
```swift
// BEFORE (v4)
protocol ConnectionProtocol {
    var type: DittoConnectionType { get }
    var id: String { get }
    var peerKeyString1: String { get }
    var peerKeyString2: String { get }
    var approximateDistanceInMeters: Double? { get }  // removed in v5
}

// AFTER (v5)
protocol ConnectionProtocol {
    var type: DittoConnectionType { get }
    var id: String { get }
    var peerKeyString1: String { get }
    var peerKeyString2: String { get }
    // approximateDistanceInMeters removed — not available in DittoConnection v5
}
```

**`MockConnection` change:**
```swift
// BEFORE (v4)
struct MockConnection: ConnectionProtocol {
    let peerKeyString1: String
    let peerKeyString2: String
    let approximateDistanceInMeters: Double?
    init(type:id:peerKeyString1:peerKeyString2:approximateDistanceInMeters:) { ... }
}

// AFTER (v5)
struct MockConnection: ConnectionProtocol {
    let peerKeyString1: String
    let peerKeyString2: String
    // approximateDistanceInMeters removed
    init(type:id:peerKeyString1:peerKeyString2:) { ... }
}
```

**Source:** Skill file covers `peerKeyString → peerKey` and `isConnectedToDittoCloud → isConnectedToDittoServer`. The skill file does NOT cover `DittoConnection.peerKeyString1/2 → peer1/2` or `DittoPeer.osV2 → os` or the removal of `approximateDistanceInMeters`. These were discovered by inspecting the v5 `.swiftinterface` file.

---

### Fix 5 — `SystemRepository.swift` line 62: `DittoPeer.osV2` renamed

**Error:** `value of type 'DittoPeer' has no member 'osV2'`

**Before:**
```swift
guard let dittoOS = peer.osV2 else { return nil }
```

**After:**
```swift
guard let dittoOS = peer.os else { return nil }
```

**Source:** NOT in skill file. Discovered by inspecting the v5 `.swiftinterface`. The property `osV2: DittoPeerOS?` was renamed to `os: DittoPeerOS?` in v5.

---

### Fix 6 — `SystemRepository.swift` line 141: `Predicate<DittoConnection>` filter ambiguity

**Error:** `trailing closure passed to parameter of type 'Predicate<DittoConnection>' that does not accept a closure`

**Root cause:** In v5, `DittoConnection` now conforms to `Identifiable`, `Equatable`, `Hashable`, and `Sendable`. In Swift 6, the `Foundation.filter(_:Predicate)` overload takes precedence over `Sequence.filter(_:)` for some types when the closure syntax is ambiguous. Explicitly typing the closure parameter resolves the ambiguity.

Additionally, this callsite directly accessed `$0.peerKeyString1` and `$0.peerKeyString2` on `DittoConnection` values. These were renamed to `peer1` and `peer2` in v5. We used the v5 native names here (not the bridge) to avoid any potential ambiguity.

**Before:**
```swift
let peerConnections: [DittoConnection] = if let localKey = localPeerKeyString {
    rawConnections.filter {
        $0.peerKeyString1 == localKey || $0.peerKeyString2 == localKey
    }
} else {
    rawConnections
}
```

**After:**
```swift
let peerConnections: [DittoConnection] = if let localKey = localPeerKeyString {
    rawConnections.filter { (conn: DittoConnection) in
        conn.peer1 == localKey || conn.peer2 == localKey
    }
} else {
    rawConnections
}
```

**Source:** NOT in skill file. The `Predicate` ambiguity is a Swift 6 + new conformances interaction not documented anywhere in the skill file.

---

### Fix 7 — `SystemRepository.swift` lines 157-159: `DittoConnection` property renames in `ConnectionInfo` constructor

**Error:** (cascading from `peerKeyString1/2` removal)

**Before:**
```swift
let mapped = deduplicated.map { connection in
    ConnectionInfo(
        id: connection.id,
        type: self.convertConnectionType(connection.type),
        peerKeyString1: connection.peerKeyString1,
        peerKeyString2: connection.peerKeyString2,
        approximateDistanceInMeters: connection.approximateDistanceInMeters
    )
}
```

**After:**
```swift
let mapped = deduplicated.map { connection in
    ConnectionInfo(
        id: connection.id,
        type: self.convertConnectionType(connection.type),
        peerKeyString1: connection.peer1,
        peerKeyString2: connection.peer2,
        approximateDistanceInMeters: nil // removed in Ditto SDK v5
    )
}
```

Note: The local `ConnectionInfo` model still has `approximateDistanceInMeters: Double?` as an optional field — it is preserved for forward compatibility and UI display code. It is simply always `nil` now. This is safe because all existing UI code guards on `if let dist = conn.approximateDistanceInMeters`.

**Source:** Partially in skill file (`DittoConnection` property renames NOT covered). The `approximateDistanceInMeters` removal is NOT in the skill file.

---

### Fix 8 — `DittoManager.swift` line 122: Actor isolation violation in auth handler

**Error:** `actor-isolated property 'appState' cannot be accessed from outside of the actor`

**Root cause:** In v5, `ditto.auth?.expirationHandler` is a `@Sendable` closure executed on an arbitrary thread, outside the `DittoManager` actor's isolation domain. The existing `Task { self.appState?.setError(error) }` creates an unstructured task but doesn't `await` the actor-isolated property access — in Swift 6's strict concurrency checking, accessing `self.appState` (an actor-isolated var) without `await` is a compile error.

**Before:**
```swift
if let error {
    Task {
        self.appState?.setError(error)
    }
}
```

**After:**
```swift
if let error {
    Task {
        await self.appState?.setError(error)
    }
}
```

The `Task { }` creates a new async context. Inside it, `self.appState` is accessed on the `DittoManager` actor, which requires `await` since the task isn't already on the actor. Adding `await` satisfies Swift 6's strict concurrency rules.

**Source:** NOT in skill file. This is a Swift 6 strict concurrency error triggered by the v5 SDK's `@Sendable` annotation on `expirationHandler`. The skill file shows correct usage patterns but does not warn about actor isolation requirements when the auth handler closure accesses actor-isolated state.

---

## 4. Skill File Accuracy Assessment

### What the Skill File Got Right

| Area | Accuracy |
|------|----------|
| `Ditto.open(config:)` async factory | Correct — already used in codebase |
| `DittoConfig(databaseID:connect:)` struct shape | Correct |
| `ditto.sync.start()` / `.stop()` / `.isActive` | Correct — already used in codebase |
| `expirationHandler` closure pattern for auth | Correct |
| `for try await` AsyncSequence for observers | Correct (but callback form still compiles in v5 — not removed) |
| `ditto.presence.observe(didChangeHandler:)` | Correct — already used in codebase |
| `isConnectedToDittoCloud` → `isConnectedToDittoServer` | Correct |
| `peerKeyString` → `peerKey` (on `DittoPeer`) | Correct |
| `diskUsage.exec` → `diskUsage.item` | Correct |
| `DiskUsageItem` → `DittoDiskUsageItem` | Correct |
| `DiskUsageObserverHandle` → `DittoDiskUsageObserver` | Correct (not used in this codebase) |
| `ditto.isActivated` replacing `ditto.activated` | Correct (not used in this codebase) |

### What the Skill File Got Wrong or Missed

| Area | Issue |
|------|-------|
| `DittoConnection.peerKeyString1/2` | **MISSING** — renamed to `peer1`/`peer2` in v5. This is a critical omission. |
| `DittoPeer.osV2` | **MISSING** — renamed to `os` in v5. |
| `DittoConnection.approximateDistanceInMeters` | **MISSING** — completely removed in v5, no replacement. This is a breaking change. |
| `Log` → `Logger` | **MISLEADING** — no clarification that this is `DittoSwift.Log`, not user-defined `Log` types. |
| Swift 6 actor isolation in auth handler | **MISSING** — `@Sendable` closure requires `await` for actor-isolated state access. |
| `Predicate<T>` filter ambiguity | **MISSING** — new `DittoConnection` conformances (`Identifiable`, `Equatable`, `Hashable`, `Sendable`) cause `filter` closure to resolve to `Foundation.Predicate` overload in Swift 6. |
| `DittoDiskUsageItem` property names | **INCOMPLETE** — skill file says type renames but doesn't confirm `.path`, `.sizeInBytes`, `.childItems` stability. (They did stay stable in rc.1.) |
| Callback `registerObserver` status | **AMBIGUOUS** — skill file implies callback form is gone, but it still compiles in v5. Should clarify: deprecated, not removed. |
| `DittoLogger` API changes | **NOT COVERED** — `DittoLogger.minimumLogLevel`, `.isEnabled`, `.setCustomLogCallback` not addressed. |
| `presence.graph.remotePeers` snapshot | **NOT COVERED** — synchronous snapshot access not documented. |
| `presence.setPeerMetadata(_:)` | **NOT COVERED** |
| `ditto.setOfflineOnlyLicenseToken(_:)` | **NOT COVERED** |
| `DittoPeer.identityServiceMetadata` / `peerMetadata` | **NOT COVERED** |
| `DittoPeer.dittoSDKVersion` | **NOT COVERED** |

---

## 5. Gaps in the Skill File — Specific Additions Needed

The following additions would make the skill file complete for real-world migrations:

### 5.1 `DittoConnection` Property Renames (CRITICAL)

```markdown
## DittoConnection Property Renames (v5)

| v4.14 | v5.0 |
|-------|------|
| `connection.peerKeyString1` | `connection.peer1` |
| `connection.peerKeyString2` | `connection.peer2` |
| `connection.approximateDistanceInMeters` | **REMOVED — no replacement** |
```

The `approximateDistanceInMeters` removal is especially important because:
- Apps using it must store `nil` now or remove the property from their own models
- UI displaying "distance to peer" must be gracefully hidden
- It was the only way to display physical proximity between devices

### 5.2 `DittoPeer.osV2` → `DittoPeer.os` (CRITICAL)

```markdown
## DittoPeer Property Renames (v5)

| v4.14 | v5.0 |
|-------|------|
| `peer.peerKeyString` | `peer.peerKey` |
| `peer.osV2: DittoPeerOS?` | `peer.os: DittoPeerOS?` |
| `peer.isConnectedToDittoCloud` | `peer.isConnectedToDittoServer` |
```

### 5.3 `DittoConnection` New Protocol Conformances and Swift 6 `filter` Ambiguity

```markdown
## Breaking: DittoConnection Conformances Cause Swift 6 `filter` Ambiguity

In v5, `DittoConnection` gains `Identifiable`, `Equatable`, `Hashable`, and `Sendable` conformances.
In Swift 6, `Foundation.filter(_:Predicate)` takes precedence over `Sequence.filter(_:)` when the
element type conforms to these protocols, causing an unexpected compile error.

**Error:** `trailing closure passed to parameter of type 'Predicate<DittoConnection>'`

**Fix:** Annotate the closure parameter type explicitly:
```swift
// BROKEN in Swift 6
connections.filter { $0.peer1 == localKey }

// FIXED
connections.filter { (conn: DittoConnection) in conn.peer1 == localKey }
```
```

### 5.4 Auth Handler — Swift 6 Actor Isolation

```markdown
## Auth Handler: Swift 6 Actor Isolation Requirement

If your `DittoManager` (or whatever class holds the `Ditto` instance) is an `actor`,
the `expirationHandler` closure is `@Sendable` and executes off the actor. Any access
to actor-isolated state inside a `Task { }` block requires `await`:

```swift
// BROKEN — Swift 6 strict concurrency error
ditto.auth?.expirationHandler = { dittoAuth, secondsRemaining in
    if let error = someError {
        Task {
            self.myActorIsolatedProperty = error  // ← error: actor-isolated
        }
    }
}

// FIXED
ditto.auth?.expirationHandler = { dittoAuth, secondsRemaining in
    if let error = someError {
        Task {
            await self.myActorIsolatedProperty = error  // ← correct
        }
    }
}
```
```

### 5.5 Callback `registerObserver` — Clarify It Is Deprecated, Not Removed

```markdown
## Observer Migration: Callback Form Still Compiles in v5

The callback-based `registerObserver` overload is **deprecated but NOT removed** in v5.0.0-rc.1.
Code using the callback pattern will still compile. The `for try await` AsyncSequence pattern
is the preferred v5 API and should be adopted for new code, but existing callback-based observers
do not need to be migrated immediately.

The types also change: `DittoStoreObserver` still exists but `Task<Void, any Error>` is
the idiomatic holder for AsyncSequence-based observer lifecycles.
```

### 5.6 `DittoDiskUsageItem` Property Stability

```markdown
## DittoDiskUsageItem Property Names (v5, Unchanged)

Despite the type rename from `DiskUsageItem` to `DittoDiskUsageItem`, the property names
are **unchanged** in v5:

- `.path: String` — unchanged
- `.sizeInBytes: Int` — unchanged
- `.childItems: [DittoDiskUsageItem]` — unchanged (type renamed, property name same)
```

### 5.7 `Log` → `Logger` Clarification

```markdown
## `Log` → `Logger` Rename: Clarification

The `DittoSwift.Log` SDK class is renamed to `DittoSwift.Logger` in v5.

**Important:** This only affects code that directly imports and uses the Ditto SDK's `Log` type.
Apps that define their own `Log` wrapper (e.g., a CocoaLumberjack facade) are unaffected.
Apps that use `DittoLogger` for SDK log configuration are also unaffected — `DittoLogger`
is a separate type that does not change name.

To check if you're affected, search for `import DittoSwift` files that also reference `Log.`
(not `DittoLogger.`).
```

---

## 6. Verified Stable APIs (Not Mentioned in Skill File)

The following APIs were used in this codebase and found to be **unchanged** in v5.0.0-rc.1:

| API | Status |
|-----|--------|
| `DittoPeer.deviceName: String` | Unchanged |
| `DittoPeer.dittoSDKVersion: String?` | Unchanged |
| `DittoPeer.connections: [DittoConnection]` | Unchanged |
| `DittoPeer.identityServiceMetadata: [String: Any?]` | Unchanged |
| `DittoPeer.peerMetadata: [String: Any?]` | Unchanged |
| `DittoConnection.id: String` | Unchanged |
| `DittoConnection.type: DittoConnectionType` | Unchanged |
| `DittoDiskUsageItem.path: String` | Unchanged |
| `DittoDiskUsageItem.sizeInBytes: Int` | Unchanged |
| `DittoDiskUsageItem.childItems: [DittoDiskUsageItem]` | Unchanged |
| `DittoLogger.minimumLogLevel` | Unchanged |
| `DittoLogger.isEnabled` | Unchanged |
| `DittoLogger.setCustomLogCallback` | Unchanged |
| `ditto.presence.graph.remotePeers` | Unchanged |
| `ditto.presence.observe { }` (callback form) | Unchanged |
| `ditto.presence.setPeerMetadata(_:)` | Unchanged |
| `ditto.store.execute(query:)` | Unchanged |
| `ditto.store.registerSubscription(query:)` via `ditto.sync` | Unchanged |
| `ditto.setOfflineOnlyLicenseToken(_:)` | Unchanged |
| `DittoDiskUsage` property on `ditto` | `ditto.diskUsage: DittoDiskUsage` unchanged |

---

## 7. Files Modified

| File | Change Type | Errors Fixed |
|------|-------------|-------------|
| `SwiftUI/EdgeStudio/Data/Repositories/StorageRepository.swift` | API rename | #1, #2 |
| `SwiftUI/EdgeStudio/Components/PresenceViewer/PresenceProtocols.swift` | Protocol bridge + API removal | #3, #4, and cascading errors |
| `SwiftUI/EdgeStudio/Data/Repositories/SystemRepository.swift` | Direct property access fix | #5, #6, #7 (filter ambiguity + peerKeyString1/2) |
| `SwiftUI/EdgeStudio/Data/DittoManager.swift` | Actor isolation fix | #8 |

---

## 8. Final Recommendation

### Is the Skill File Ready for Customers?

**NO — requires additions before it is production-ready.**

### Priority

**Must add (blockers):**
1. `DittoConnection.peerKeyString1/2` → `peer1/peer2` rename
2. `DittoConnection.approximateDistanceInMeters` removal (breaking change with no replacement)
3. `DittoPeer.osV2` → `os` rename
4. Swift 6 actor isolation requirement in `expirationHandler`
5. `Predicate<DittoConnection>` filter ambiguity in Swift 6

**Should add (important for accuracy):**
6. Clarify `Log` → `Logger` is `DittoSwift.Log`, not user-defined types
7. State that callback `registerObserver` is deprecated but not removed
8. List `DittoDiskUsageItem` property names as stable

**Nice to have (completeness):**
9. Table of verified-stable APIs that are commonly used but not mentioned
10. Note on `ditto.presence.graph.remotePeers` synchronous snapshot access

### What the Migration Actually Required

This migration was straightforward because the codebase had already adopted most v5 APIs in a previous partial migration. The remaining v4 API usages required **4 files** with **8 distinct types of changes**. The total scope was small (~20 lines changed), but 5 of the 8 change types were not covered by the skill file:

- `DittoConnection.peer1/peer2` renames
- `DittoConnection.approximateDistanceInMeters` removal
- `DittoPeer.os` rename (from `osV2`)
- Swift 6 actor isolation in `@Sendable` closures
- `Predicate` overload ambiguity from new `DittoConnection` conformances

The skill file would have gotten a developer 60% of the way there on this codebase. The remaining 40% required inspecting the `.swiftinterface` file directly.
