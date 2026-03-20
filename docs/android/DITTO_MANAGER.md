# DittoManager — Android

`DittoManager` (`data/ditto/DittoManager.kt`) is the single point of ownership for the active Ditto SDK instance in Edge Studio for Android.

---

## Lifecycle

### `hydrate(database: DittoDatabase): Ditto`

Tears down any previously active Ditto instance, creates a new one configured for the given database, and starts sync.

**Steps:**
1. `closeCurrentInstance()` — stops sync and nulls the current instance
2. `Ditto(identity, context)` on `Dispatchers.IO`
3. Sets presence metadata (`deviceName = "Edge Studio"`)
4. Calls `applyTransportConfig()` (applies BLE / LAN / WiFi Aware / WebSocket settings)
5. `startSync()` on `Dispatchers.IO`
6. Stores and returns the instance

Called from `MainStudioViewModel.hydrate()` on `init`.

### `close()`

Stops sync and clears the instance. Called from `MainStudioViewModel.onCleared()` when the user closes the studio screen.

### `currentInstance(): Ditto?`

Returns the active Ditto instance or `null` if not yet hydrated / already closed.

---

## Transport Configuration

### `applyTransportConfig(ditto: Ditto, database: DittoDatabase)`

Updates the Ditto transport config based on database settings:

| Setting | Transport |
|---------|-----------|
| `isBluetoothLeEnabled` | `peerToPeer.bluetoothLE.isEnabled` |
| `isLanEnabled` | `peerToPeer.lan.isEnabled` |
| `isAwdlEnabled` | `peerToPeer.wifiAware.isEnabled` |
| `isCloudSyncEnabled` + `websocketUrl` | `connect.websocketUrls` |

Called during `hydrate()` and from `MainStudioViewModel.applyTransportSettings()` when the user changes transport settings at runtime.

---

## Auth Identity

| `AuthMode` | Identity |
|-----------|----------|
| `SERVER` | `DittoIdentity.OnlineWithAuthentication` — token-based login with `authHandler` |
| `SMALL_PEERS_ONLY` | `DittoIdentity.OfflinePlayground` — no cloud, P2P only |

---

## Dispatcher Constraint

All Ditto SDK operations (`Ditto()`, `startSync()`, `stopSync()`) run on `Dispatchers.IO`.

> **Note (SDKS-1294):** The `Dispatchers.IO` restriction only affects Kotlin Multiplatform targeting iOS. Android-native Ditto is not subject to this constraint — `Dispatchers.IO` is used here as a best practice for background operations, not because the SDK requires it.

---

## DI Registration

```kotlin
// data/di/DataModule.kt
single { DittoManager(androidContext()) }
```

`DittoManager` is a Koin `single` — one instance shared across all ViewModels.

---

## Usage

```kotlin
class MainStudioViewModel(
    private val dittoManager: DittoManager,
    ...
) : ViewModel() {

    init {
        viewModelScope.launch {
            val ditto = dittoManager.hydrate(database)
            systemRepository.startObserving(ditto)
        }
    }

    override fun onCleared() {
        super.onCleared()
        viewModelScope.launch { dittoManager.close() }
    }
}
```
