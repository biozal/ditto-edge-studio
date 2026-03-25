# DittoManager Authentication Plan

## Problem

`DittoManager.hydrate()` creates a Ditto instance but never registers an auth expiration handler. For `SERVER` mode databases:

- Ditto calls the expiration handler **immediately** on startup to perform initial login
- Without the handler, the instance never authenticates and sync cannot start
- Without the handler, tokens are never refreshed when they expire mid-session

For `SMALL_PEERS_ONLY` mode databases:

- The Ditto instance requires an offline license token to operate
- Without calling `setOfflineOnlyLicenseToken()`, the instance will not sync

## Reference Implementation

The SwiftUI app (`DittoManager.swift`, lines 115–133) handles both cases:

```swift
// Server mode: auth expiration handler
ditto.auth?.expirationHandler = { dittoAuth, secondsRemaining in
    dittoAuth.auth?.login(token: databaseConfig.token, provider: .development) { _, error in
        if let error { /* log error */ }
        else { Log.info("[Auth] Authentication successful \(secondsRemaining)") }
    }
}

// SmallPeersOnly mode: offline license token
if mode == .smallPeersOnly && !token.isEmpty {
    try ditto.setOfflineOnlyLicenseToken(token)
}
```

The Ditto docs (https://docs.ditto.live/sdk/latest/ditto-config) confirm the Kotlin pattern:

```kotlin
ditto.auth?.expirationHandler = { ditto, secondsRemaining ->
    ditto.auth?.login(token = "TOKEN", provider = DittoAuthenticationProvider.development())
}
```

## Changes Required

### 1. `data/ditto/DittoManager.kt`

**a) Add `setupAuth()` private function**

Called inside `hydrate()` after creating the instance, before starting sync:

```kotlin
private fun setupAuth(ditto: Ditto, database: DittoDatabase) {
    when (database.mode) {
        AuthMode.SERVER -> {
            ditto.auth?.expirationHandler = { d, secondsRemaining ->
                android.util.Log.i("DittoManager", "[Auth] Handler called, secondsRemaining=$secondsRemaining")
                d.auth?.login(
                    token = database.token,
                    provider = DittoAuthenticationProvider.development(),
                )
            }
        }
        AuthMode.SMALL_PEERS_ONLY -> {
            if (database.token.isNotEmpty()) {
                runCatching { ditto.setOfflineOnlyLicenseToken(database.token) }
                    .onFailure { e ->
                        android.util.Log.e("DittoManager", "[Auth] Failed to set offline license token: ${e.message}")
                    }
            }
        }
    }
}
```

**b) Update `hydrate()` to call `setupAuth()`**

Insert `setupAuth(newDitto, database)` after creating the instance and before `applyTransportConfig()`:

```kotlin
suspend fun hydrate(database: DittoDatabase): Ditto {
    closeCurrentInstance()

    val config = buildConfig(database)
    val newDitto = withContext(Dispatchers.IO) {
        DittoFactory.create(config, coroutineScope)
    }

    // Set device name for peer identification
    newDitto.deviceName = "Edge Studio"

    // Register auth handler BEFORE starting sync
    setupAuth(newDitto, database)                    // ← NEW

    // Apply transport config BEFORE starting sync
    applyTransportConfig(newDitto, database)

    withContext(Dispatchers.IO) { newDitto.sync.start() }

    ditto = newDitto
    return newDitto
}
```

**c) Add input validation**

Mirror the iOS guard that prevents creating an instance with missing credentials:

```kotlin
suspend fun hydrate(database: DittoDatabase): Ditto {
    require(database.databaseId.isNotBlank()) { "databaseId must not be blank" }
    if (database.mode == AuthMode.SERVER) {
        require(database.token.isNotBlank()) { "token must not be blank for SERVER mode" }
        require(database.authUrl.isNotBlank()) { "authUrl must not be blank for SERVER mode" }
    }
    // … rest of hydrate
}
```

### 2. `test/data/ditto/DittoManagerTest.kt`

Add tests covering the new auth setup:

- **`SERVER` mode**: verify `expirationHandler` is set on `ditto.auth` after `hydrate()`
- **`SMALL_PEERS_ONLY` with token**: verify `setOfflineOnlyLicenseToken()` is called
- **`SMALL_PEERS_ONLY` without token**: verify `setOfflineOnlyLicenseToken()` is NOT called
- **Validation**: `hydrate()` throws `IllegalArgumentException` when `databaseId` is blank
- **Validation**: `hydrate()` throws `IllegalArgumentException` when `token` is blank for `SERVER` mode

## SDK API Notes

Based on the Android SDK AAR (verified via decompilation) and Ditto docs:

| Operation | Android API |
|-----------|-------------|
| Auth expiration handler | `ditto.auth?.expirationHandler = { d, secondsRemaining -> ... }` |
| Login (server mode) | `ditto.auth?.login(token = "...", provider = DittoAuthenticationProvider.development())` |
| Offline license token | `ditto.setOfflineOnlyLicenseToken("...")` |

The `expirationHandler` lambda receives `(Ditto, Int)` — the `Ditto` instance and seconds remaining before expiry (0 = initial login required).

`DittoAuthenticationProvider.development()` matches the iOS `.development` enum case and is correct for playground / dev environments.

## Order of Operations in `hydrate()`

The correct ordering is important:

1. `DittoFactory.create(config, coroutineScope)` — create instance
2. `newDitto.deviceName = "Edge Studio"` — set metadata
3. `setupAuth(newDitto, database)` — register auth handler ← must be before sync
4. `applyTransportConfig(newDitto, database)` — configure transports
5. `newDitto.sync.start()` — begin sync (auth handler fires here for SERVER mode)

## Files Modified

| File | Change |
|------|--------|
| `app/src/main/java/.../data/ditto/DittoManager.kt` | Add `setupAuth()`, call it in `hydrate()`, add validation |
| `app/src/test/java/.../data/ditto/DittoManagerTest.kt` | Add auth setup test cases |
