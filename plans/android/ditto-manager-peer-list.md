# Android DittoManager + Peer List — Implementation Plan

**Status:** ✅ IMPLEMENTED (2026-03-08)

---

## Summary

Implemented Ditto SDK v5.0.0-preview.5 integration for Android, including:

1. **Ditto SDK dependency** — `libs.versions.toml` + `build.gradle.kts`
2. **Runtime permissions** — Bluetooth LE, WiFi, Location / NEARBY_WIFI_DEVICES
3. **DittoManager** — single Ditto instance lifecycle (hydrate, close, transport config)
4. **Domain models** — `SyncStatusInfo`, `LocalPeerInfo`, `ConnectionsByTransport`, `NetworkInterfaceInfo`, `P2PTransportInfo`
5. **SystemRepository** — presence observation via `ditto.presence.observe {}` → `StateFlow`
6. **NetworkDiagnosticsRepository** — `java.net.NetworkInterface` + `WifiManager` + `ConnectivityManager` + `WifiAwareManager`
7. **MainStudioViewModel** — updated to wire Ditto lifecycle, peers, and network diagnostics
8. **Composables** — `LocalPeerCard`, `RemotePeerCard`, `NetworkInterfaceCard`, `P2PTransportCard`, `ConnectedPeersScreen`
9. **MainStudioScreen** — Peers List tab wired to `ConnectedPeersScreen`
10. **Tests** — unit + instrumented

---

## Files Created / Modified

| Action | File |
|--------|------|
| **Modified** | `android/gradle/libs.versions.toml` |
| **Modified** | `android/app/build.gradle.kts` |
| **Modified** | `android/app/src/main/AndroidManifest.xml` |
| **Modified** | `data/db/dao/DatabaseConfigDao.kt` — added `getById(Long)` |
| **Modified** | `data/repository/DatabaseRepository.kt` — added `getById(Long)` |
| **Modified** | `data/repository/DatabaseRepositoryImpl.kt` — implemented `getById` |
| **Modified** | `data/di/DataModule.kt` — added DittoManager, SystemRepository, NetworkDiagnosticsRepository |
| **Modified** | `viewmodel/MainStudioViewModel.kt` — full rewrite with Ditto lifecycle |
| **Modified** | `ui/mainstudio/MainStudioScreen.kt` — wired peers, transport, bottom bar |
| **Created** | `domain/model/SyncStatusInfo.kt` |
| **Created** | `domain/model/LocalPeerInfo.kt` |
| **Created** | `domain/model/ConnectionsByTransport.kt` |
| **Created** | `domain/model/NetworkInterfaceInfo.kt` |
| **Created** | `domain/model/P2PTransportInfo.kt` |
| **Created** | `data/ditto/DittoManager.kt` |
| **Created** | `data/repository/SystemRepository.kt` |
| **Created** | `data/repository/SystemRepositoryImpl.kt` |
| **Created** | `data/repository/NetworkDiagnosticsRepository.kt` |
| **Created** | `data/repository/NetworkDiagnosticsRepositoryImpl.kt` |
| **Created** | `ui/mainstudio/DittoPermissionHandler.kt` |
| **Created** | `ui/mainstudio/GradientCard.kt` |
| **Created** | `ui/mainstudio/LocalPeerCard.kt` |
| **Created** | `ui/mainstudio/RemotePeerCard.kt` |
| **Created** | `ui/mainstudio/NetworkInterfaceCard.kt` |
| **Created** | `ui/mainstudio/P2PTransportCard.kt` |
| **Created** | `ui/mainstudio/ConnectedPeersScreen.kt` |
| **Created** | `test/viewmodel/MainStudioViewModelTest.kt` |
| **Created** | `test/data/repository/SystemRepositoryTest.kt` |
| **Created** | `test/data/repository/NetworkDiagnosticsRepositoryTest.kt` |
| **Created** | `test/domain/model/NetworkInterfaceInfoTest.kt` |
| **Created** | `androidTest/ui/mainstudio/ConnectedPeersScreenTest.kt` |
| **Created** | `docs/android/DITTO_MANAGER.md` |
| **Created** | `docs/android/NETWORK_DIAGNOSTICS.md` |
| **Updated** | `docs/android/ARCHITECTURE.md` |

---

## Ditto SDK API Notes

The DittoManager uses the following Ditto SDK v5 APIs. If these don't compile exactly, adjust to match the actual SDK types after Gradle sync:

- `DittoIdentity.OnlineWithAuthentication` — for `AuthMode.SERVER`
- `DittoIdentity.OfflinePlayground` — for `AuthMode.SMALL_PEERS_ONLY`
- `ditto.presence.observe { graph -> }` — presence callback, returns `DittoPresenceObserver`
- `graph.localPeer.peerKeyString` — local peer identity
- `graph.remotePeers` — list of connected remote peers
- `peer.peerKeyString`, `peer.deviceName`, `peer.dittoSdkVersion`, `peer.osType`, `peer.connections`
- `conn.id`, `conn.connectionType`, `conn.approximateDistanceInMeters`
- `ditto.transportConfig` — mutable transport config property
- `ditto.isSyncActive` — sync state
- `ditto.startSync()` / `ditto.stopSync()`
- `ditto.presence.setMetadata(Map)` — set peer metadata

> After Gradle sync, compile errors in `DittoManager.kt` or `SystemRepositoryImpl.kt` may indicate minor API differences between preview.5 and what's documented here. Adjust field names / method signatures accordingly.
