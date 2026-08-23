# DittoManager — Android

`DittoManager` (`data/ditto/DittoManager.kt`) is the single point of ownership for the active Ditto SDK instance in Edge Studio for Android. Built against Ditto SDK 5.1.x (`com.ditto:ditto-kotlin-android`).

---

## Lifecycle

### `hydrate(database: DittoDatabase): Ditto`

Tears down any previously active Ditto instance, creates a new one configured for the given database, and starts sync.

**Steps:**
1. Validates the config (blank `databaseId`, missing token/authUrl for `SERVER` mode, and unreadable collection sync scopes all fail fast — fail-closed, see `docs/ADVANCED_DATABASE_CONFIG.md`)
2. `closeCurrentInstance()` — closes the previous instance (releases the persistence-directory lock) and nulls it
3. Builds a `DittoConfig` and calls `DittoFactory.create(config, coroutineScope)` on `Dispatchers.IO`
4. Sets `deviceName = "Edge Studio"` and peer metadata (`presence.peerMetadataJsonString`) so the peer is identifiable in the mesh
5. `setupAuth()` — registers the auth handler **before** starting sync
6. `runOpenSequence()` — applies advanced configuration and starts sync in the mandated order: user startup settings → transports → `DQL_STRICT_MODE` → collection sync scopes → `startSync()` (see `AdvancedSettingsApplier.OpenSequence`)
7. Stores and returns the instance

Called from `StudioSession` (which `MainStudioViewModel` drives) when a studio screen opens for a database.

### `close()`

Stops sync and closes the instance. **Not** called from `MainStudioViewModel.onCleared()` — the session deliberately outlives the ViewModel (each studio rail section is its own back-stack entry, so clearing one VM must not tear the session down). Instead:

- `DittoManager` is injected into the Koin `studio`-scoped `StudioSession` (`data/session/StudioSession.kt`)
- The scope is declared in `DataModule.kt` with `onClose { it?.close() }`, and `StudioSession.close()` calls `dittoManager.close()` exactly once
- The scope is closed by `StudioScopeManager` (`ui/navigation/StudioScopeManager.kt`, driven from `AppNavGraph`) when no studio entry for the `databaseId` remains on the back stack

`closeCurrentInstance()` nulls the reference first (so concurrent `currentInstance()` calls see `null` immediately), then calls `Ditto.close()` on `Dispatchers.IO` — closing cancels the Ditto coroutine scope and releases the persistence-directory lock; stopping sync alone is not sufficient and the next `DittoFactory.create()` on the same `databaseId` would fail with a file-lock error.

### `currentInstance(): Ditto?`

Returns the active Ditto instance or `null` if not yet hydrated / already closed.

### `startSync()` / `resetSystemSettingsToDefaults(database)`

`startSync()` re-applies the full open sequence on the current instance (every sync-start path funnels through it, because `ALTER SYSTEM` state is in-memory only and scopes must be re-applied and re-verified). `resetSystemSettingsToDefaults()` stops sync first, runs `ALTER SYSTEM RESET ALL`, then re-applies everything through the same open sequence. `refreshActiveConfigIfMatching(database)` keeps the manager's copy of the active config current across edit-saves.

---

## Instance Creation (Ditto SDK 5.1)

Instances are created with the factory + config API, not a constructor:

```kotlin
val config = when (database.mode) {
    AuthMode.SERVER -> DittoConfig(
        databaseId = database.databaseId,
        connect = DittoConfig.Connect.Server(url = database.authUrl),
    )
    AuthMode.SMALL_PEERS_ONLY -> DittoConfig(
        databaseId = database.databaseId,
        connect = DittoConfig.Connect.SmallPeersOnly(),
    )
}
val ditto = DittoFactory.create(config, coroutineScope)
```

`coroutineScope` is injected into `DittoManager`'s constructor; the SDK ties the instance's internal coroutines to it, and `Ditto.close()` cancels that scope.

## Auth

| `AuthMode` | Config | Runtime auth |
|-----------|--------|--------------|
| `SERVER` | `DittoConfig.Connect.Server(url = authUrl)` | `ditto.auth.expirationHandler` logs in with the stored token via `DittoAuthenticationProvider.development()` |
| `SMALL_PEERS_ONLY` | `DittoConfig.Connect.SmallPeersOnly()` | `ditto.setOfflineOnlyLicenseToken(token)` when a token is present |

---

## Transport Configuration

### `applyTransportConfig(ditto: Ditto, database: DittoDatabase)`

Updates the Ditto transport config based on database settings:

| Setting | Transport |
|---------|-----------|
| `isBluetoothLeEnabled` | `peerToPeer.bluetoothLe.enabled` |
| `isLanEnabled` | `peerToPeer.lan.enabled` |
| `isAwdlEnabled` | `peerToPeer.wifiAware.enabled` |
| `isCloudSyncEnabled` + `websocketUrl` | `connect.websocketUrls` |

Called during `hydrate()` (inside the open sequence) and from `StudioSession.applyTransportSettings()` when the user changes transport settings at runtime.

---

## Dispatcher Constraint

All Ditto SDK operations (`DittoFactory.create()`, `sync.start()`, `sync.stop()`, `close()`) run on `Dispatchers.IO`.

> **Note (SDKS-1294):** The `Dispatchers.IO` restriction only affects Kotlin Multiplatform targeting iOS. Android-native Ditto is not subject to this constraint — `Dispatchers.IO` is used here as a best practice for background operations, not because the SDK requires it.

---

## DI Registration

```kotlin
// data/di/DataModule.kt
single { DittoManager(get<CoroutineScope>(), get<DittoLogCaptureService>()) }
```

`DittoManager` is a Koin `single` — one instance shared across the app. When a `DittoLogCaptureService` is present, `hydrate()` also sets `DittoLogger.minimumLogLevel = DittoLogLevel.Info` (adjustable from the Log Analyzer UI).

---

## Usage

```kotlin
// StudioSession (Koin "studio" scope, one per open database) owns the lifecycle:
class StudioSession(
    private val dittoManager: DittoManager,
    ...
) {
    fun hydrate() {
        sessionScope.launch {
            val ditto = dittoManager.hydrate(database)
            systemRepository.startObserving(ditto)
            collectionsRepository.startObserving(ditto)
            // ... register saved subscriptions/observers ...
        }
    }

    fun close() {
        if (!closed.compareAndSet(false, true)) return   // exactly-once
        // ... release SDK handles + reset state inline, then dispatch the
        // suspending close to the process-wide DittoTeardownRegistry so it
        // survives this session's own scope cancellation:
        DittoTeardownRegistry.launchClose(databaseId, teardownDispatcher) {
            withContext(NonCancellable) { dittoManager.close() }
        }
    }
}

// MainStudioViewModel deliberately does NOT close the session from onCleared();
// teardown is driven by the Koin scope's onClose hook via StudioScopeManager.
```
