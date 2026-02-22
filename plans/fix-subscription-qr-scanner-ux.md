# Plan: Fix Subscription QR Scanner UX

**Branch:** `release-1.0.0-qr-fv`
**Status:** Ready for review
**Date:** 2026-02-22

---

## Problem Summary

After scanning a QR code in `SubscriptionQRScannerView`, the sheet **never dismisses**. The caller in `MainStudioView` launches a detached `Task` to import subscriptions but never calls `dismiss()`. The sheet stays on screen indefinitely with the camera still live beneath a semi-transparent overlay.

### Secondary Issues

| # | Issue | Current behaviour |
|---|-------|-------------------|
| 1 | Camera stays live | `Color.black.opacity(0.5)` overlay is translucent — user sees the live camera feed behind the "Importing..." UI |
| 2 | No progress feedback | A non-determinate `ProgressView("Importing...")` spinner gives no sense of how many items remain |
| 3 | No auto-dismiss | The import `Task` in `MainStudioView` completes but `dismiss()` is never called |

---

## Root Cause (Diagnosed)

In `MainStudioView.swift` lines 231-238:

```swift
.sheet(isPresented: $showingSubscriptionQRScanner) {
    SubscriptionQRScannerView { items in
        Task { await viewModel.importSubscriptionsFromQR(items, appState: appState) }
    }
```

`handleScanned` in `SubscriptionQRScannerView` sets `isImporting = true` and calls `onScanned(items)` synchronously. The closure fires a background `Task` and returns immediately — `dismiss()` is never scheduled. The import work happens on a detached task, and after it completes there is no callback path back to `dismiss()`.

---

## Files to Modify

| File | Role |
|------|------|
| `Views/SubscriptionQRScannerView.swift` | Replace `isImporting: Bool` with a `ScanState` enum; replace camera with solid black on scan; make `onScanned` an `async` callback with progress reporting |
| `Views/MainStudioView.swift` | Add `onProgress` parameter to `importSubscriptionsFromQR`; update sheet closure to use async callback |

---

## Detailed Changes

### Change 1 — New `ScanState` Enum in `SubscriptionQRScannerView`

Replace the simple `@State private var isImporting = false` with a typed enum that carries progress values.

**Before:**
```swift
@State private var isImporting = false
```

**After:**
```swift
private enum ScanState: Equatable {
    case scanning
    case importing(current: Int, total: Int)
}
@State private var scanState: ScanState = .scanning
```

---

### Change 2 — Camera Replaced by Solid Black Screen on Scan

Conditionally render `SubscriptionQRCameraPreview` only in the `.scanning` state. Once a scan is detected, replace the camera feed with a solid `Color.black` so no camera image bleeds through during import.

**Before:**
```swift
ZStack {
    SubscriptionQRCameraPreview(onScanned: handleScanned)
        .ignoresSafeArea()

    if isImporting {
        Color.black.opacity(0.5)
            .ignoresSafeArea()
        ProgressView("Importing...")
            .foregroundStyle(.white)
            .tint(.white)
    }
}
```

**After:**
```swift
ZStack {
    if case .scanning = scanState {
        SubscriptionQRCameraPreview(onScanned: handleScanned)
            .ignoresSafeArea()
    } else {
        Color.black.ignoresSafeArea()   // solid — camera is fully gone
    }

    if case .importing(let current, let total) = scanState {
        VStack(spacing: 20) {
            ProgressView(value: Double(current), total: Double(total))
                .progressViewStyle(.linear)
                .tint(.white)
                .padding(.horizontal, 40)
            Text("Importing \(current) of \(total)…")
                .foregroundStyle(.white)
                .font(.headline)
        }
    }
}
```

Removing `SubscriptionQRCameraPreview` from the view hierarchy stops the `DataScannerViewController` (iOS) and `AVCaptureSession` (macOS) from running, eliminating both the live video and the hardware resource usage. The determinate `ProgressView` shows real throughput ("2 of 5…") rather than an indeterminate spinner.

---

### Change 3 — `onScanned` Callback Becomes Async With Progress Closure

Change the callback type so the scanner view can `await` the entire import, receive per-item progress ticks, and then call `dismiss()` itself when the work completes.

**Before:**
```swift
let onScanned: ([SubscriptionQRItem]) -> Void
```
```swift
private func handleScanned(_ items: [SubscriptionQRItem]) {
    guard !isImporting else { return }
    isImporting = true
    onScanned(items)
}
```

**After:**
```swift
let onScanned: (_ items: [SubscriptionQRItem], _ progress: @escaping @MainActor (Int, Int) -> Void) async -> Void
```
```swift
private func handleScanned(_ items: [SubscriptionQRItem]) {
    guard case .scanning = scanState else { return }
    scanState = .importing(current: 0, total: items.count)
    Task { @MainActor in
        await onScanned(items) { current, total in
            scanState = .importing(current: current, total: total)
        }
        dismiss()
    }
}
```

Making `onScanned` `async` means `handleScanned` can `await` it and then call `dismiss()` in the same `Task` — the sheet dismisses only after all work is done. The `@MainActor` annotation on the `progress` closure ensures every `scanState` update is on the main thread and SwiftUI picks up the change immediately.

---

### Change 4 — `importSubscriptionsFromQR` in ViewModel Accepts and Calls Progress

**Before:**
```swift
func importSubscriptionsFromQR(_ items: [SubscriptionQRItem], appState: AppState) async {
    for item in items {
        var sub = DittoSubscription(id: UUID().uuidString)
        sub.name = item.name
        sub.query = item.query
        sub.args = item.args
        try? await SubscriptionsRepository.shared.saveDittoSubscription(sub)
    }
}
```

**After:**
```swift
func importSubscriptionsFromQR(
    _ items: [SubscriptionQRItem],
    appState: AppState,
    onProgress: @escaping @MainActor (Int, Int) -> Void
) async {
    let total = items.count
    for (index, item) in items.enumerated() {
        var sub = DittoSubscription(id: UUID().uuidString)
        sub.name = item.name
        sub.query = item.query
        sub.args = item.args
        try? await SubscriptionsRepository.shared.saveDittoSubscription(sub)
        await onProgress(index + 1, total)
    }
}
```

Calling `onProgress` after each successful `saveDittoSubscription` means the progress bar advances once per persisted item. Using `try?` on the save keeps the existing silent-failure-per-item behaviour so a single duplicate or storage error doesn't abort the whole import.

---

### Change 5 — Update Sheet Closure in `MainStudioView`

Remove the wrapping `Task {}` from the sheet closure and supply the new `async` signature including the progress callback.

**Before:**
```swift
.sheet(isPresented: $showingSubscriptionQRScanner) {
    SubscriptionQRScannerView { items in
        Task { await viewModel.importSubscriptionsFromQR(items, appState: appState) }
    }
    #if os(macOS)
    .frame(minWidth: 480, minHeight: 360)
    #endif
}
```

**After:**
```swift
.sheet(isPresented: $showingSubscriptionQRScanner) {
    SubscriptionQRScannerView { items, onProgress in
        await viewModel.importSubscriptionsFromQR(items, appState: appState, onProgress: onProgress)
    }
    #if os(macOS)
    .frame(minWidth: 480, minHeight: 360)
    #endif
}
```

---

## Implementation Order

1. `SubscriptionQRScannerView.swift` — Changes 1, 2, 3 (self-contained within the file)
2. `MainStudioView.swift` — Change 4 (update ViewModel method), then Change 5 (update call site)

---

## Verification Checklist

- [ ] Scan QR code → camera view is immediately replaced by a solid black screen (no video bleed)
- [ ] Progress label shows "Importing 1 of N…", "Importing 2 of N…" etc as each subscription saves
- [ ] Linear `ProgressView` bar advances in step with the label
- [ ] Sheet auto-dismisses when all subscriptions are saved (no manual tap required)
- [ ] Cancel button still works at any point during import
- [ ] Scanning the same QR code twice imports no duplicates (existing `try?` handles this)
- [ ] No crash when QR payload contains zero items
- [ ] Build succeeds:
  ```
  xcodebuild -project "Edge Debug Helper.xcodeproj" \
             -scheme "Edge Studio" \
             -destination "platform=macOS,arch=arm64" build
  ```

---

## Out of Scope

- Changes to `SubscriptionQRCameraPreview` internals — removing the view from the hierarchy tears down the camera session automatically
- Per-item error surfacing (existing `try?` silent-failure approach is intentional)
- UI tests for the scanner sheet (camera in simulator is unreliable; manual QA is appropriate)
