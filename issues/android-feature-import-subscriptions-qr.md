# Android Feature: Import/Export Subscriptions via QR Code

**Priority:** Medium  
**Complexity:** Medium  
**Status:** Not Started  
**Platforms with feature:** SwiftUI  

## Summary

Android can share database configurations via QR codes but cannot share individual subscriptions via QR. SwiftUI supports exporting the current subscription list as a QR code and importing subscriptions from another device's QR code. This enables quick subscription sharing between devices without manual re-entry.

## Current State in Android

- `QrCodeEncoder.kt` and `QrCodeDecoder.kt` exist but only handle database config + favorites (`QrCodePayload`)
- `QrScannerScreen.kt` exists with CameraX + ML Kit barcode detection — fully functional for database QR
- `QrDisplayDialog.kt` exists for showing generated QR codes
- **No subscription-specific QR encoding/decoding**
- **No subscription QR display or scan UI triggers**

## What Needs to Be Built

### 1. Subscription QR Payload Model

```kotlin
// Add to util/QrCodeEncoder.kt or new file

@Serializable
data class SubscriptionsQrPayload(
    val version: Int = 1,
    val subscriptions: List<SubscriptionQrItem>
)

@Serializable
data class SubscriptionQrItem(
    val name: String,
    val query: String,
    val args: String? = null
)
```

**QR format (matching SwiftUI):**
- Prefix: `EDS_SUBS1:`
- Payload: Base64(zlib(JSON of SubscriptionsQrPayload))
- Max payload: ~2200 characters (QR code practical limit)
- If payload exceeds limit, truncate subscription list with warning

### 2. Encoder/Decoder Extensions

Add to existing `QrCodeEncoder.kt`:

```kotlin
fun encodeSubscriptions(subscriptions: List<DittoSubscription>): Bitmap? {
    val items = subscriptions.map { SubscriptionQrItem(name = it.name, query = it.query) }
    val payload = SubscriptionsQrPayload(subscriptions = items)
    val json = Json.encodeToString(payload)
    val compressed = zlibCompress(json.toByteArray())
    val encoded = "EDS_SUBS1:" + Base64.encodeToString(compressed, Base64.NO_WRAP)
    if (encoded.length > 2200) {
        // Truncate subscriptions list and retry, or return error
    }
    return generateQrBitmap(encoded)
}
```

Add to existing `QrCodeDecoder.kt`:

```kotlin
fun decodeSubscriptions(raw: String): List<SubscriptionQrItem>? {
    if (!raw.startsWith("EDS_SUBS1:")) return null
    val base64 = raw.removePrefix("EDS_SUBS1:")
    val compressed = Base64.decode(base64, Base64.NO_WRAP)
    val json = String(zlibDecompress(compressed))
    val payload = Json.decodeFromString<SubscriptionsQrPayload>(json)
    return payload.subscriptions
}
```

### 3. Export Subscriptions QR Display

**Entry point:** Add a QR code icon button in the subscriptions sidebar header.

In SwiftUI, this is a small `qrcode` icon in the "SUBSCRIPTIONS" section header of the sidebar. When tapped, it shows a sheet with the generated QR code.

```kotlin
// In the subscriptions section of DrawerPanel/DataPanel in MainStudioScreen.kt
// Add QR icon button next to "SUBSCRIPTIONS" header

IconButton(onClick = { showSubscriptionQrDisplay = true }) {
    Icon(Icons.Default.QrCode, contentDescription = "Export Subscriptions QR")
}
```

**Display dialog (reuse QrDisplayDialog pattern):**
- Title: "Subscriptions (X)" showing count
- QR code image (250dp square)
- Subtitle: "Scan with Edge Studio on another device"
- Done button

### 4. Import Subscriptions via QR Scanner

**Entry point:** Add "Import Subscriptions → QR Code" to the FAB menu or toolbar menu.

**Scanner flow:**
1. Reuse existing `QrScannerScreen.kt` camera infrastructure
2. When a QR code is detected, check prefix:
   - `EDS2:` → existing database import flow
   - `EDS_SUBS1:` → new subscription import flow
3. Decode subscription list
4. For each subscription item:
   - Create `DittoSubscription` with auto-generated ID
   - Name: use provided name or "Imported: {query truncated}"
   - Save via `SubscriptionsRepository`
5. Show progress: "Importing X of Y..."
6. On completion, navigate back to subscriptions list

**Modification to QrScannerViewModel.kt:**

```kotlin
fun handleDetectedCode(rawValue: String) {
    // Try subscription decode first
    val subscriptions = QrCodeDecoder.decodeSubscriptions(rawValue)
    if (subscriptions != null) {
        importSubscriptions(subscriptions)
        return
    }
    // Fall back to existing database decode
    val dbPayload = QrCodeDecoder.decode(rawValue)
    // ... existing logic
}
```

### 5. Import Subscriptions from Server (Optional Enhancement)

SwiftUI also supports importing subscriptions discovered from connected peers via HTTP API (`ImportSubscriptionsView.swift`). This queries `SmallPeerInfo` to find subscriptions running on other devices and lets the user selectively import them.

This is a secondary feature that requires HTTP API configuration. Consider implementing after the QR-based import is complete.

## Key Reference Files

### SwiftUI
- `SwiftUI/EdgeStudio/Components/SubscriptionQRDisplayView.swift` — QR display UI showing encoded subscriptions
- `SwiftUI/EdgeStudio/Components/SubscriptionQRScannerView.swift` — Scanner with VisionKit, progress during import
- `SwiftUI/EdgeStudio/Components/ImportSubscriptionsView.swift` — Server-based subscription import (queries SmallPeerInfo)
- `SwiftUI/EdgeStudio/Utilities/QRCodeGenerator.swift` — Encoding/decoding with `EDS_SUBS1:` prefix, zlib compression
- `SwiftUI/EdgeStudio/Views/StudioView/SidebarViews.swift` — QR icon button in subscriptions header

### Android (existing files to modify)
- `android/app/src/main/java/com/costoda/dittoedgestudio/util/QrCodeEncoder.kt` — Add subscription encoding
- `android/app/src/main/java/com/costoda/dittoedgestudio/util/QrCodeDecoder.kt` — Add subscription decoding
- `android/app/src/main/java/com/costoda/dittoedgestudio/viewmodel/QrScannerViewModel.kt` — Handle subscription QR type
- `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/MainStudioScreen.kt` — Add export/import UI triggers

## Acceptance Criteria

- [ ] QR icon button in subscriptions sidebar header to export
- [ ] Export generates QR with `EDS_SUBS1:` prefix containing all current subscriptions
- [ ] QR display dialog shows code with subscription count
- [ ] Scanner detects and decodes subscription QR codes (distinct from database QR)
- [ ] Imported subscriptions saved to repository with proper database association
- [ ] Progress shown during multi-subscription import
- [ ] Graceful handling when payload exceeds QR capacity (truncate with warning)
- [ ] Deduplication: skip subscriptions that already exist (same query)
