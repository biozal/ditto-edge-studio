# Plan: Fix QR Import — Subscriptions Don't Appear Until Restart

**Branch:** `release-1.0.0-qr-fv`
**Status:** Ready for review
**Date:** 2026-02-22

---

## Observed Behaviour

1. Scan QR code → sheet closes quickly
2. Subscriptions list is empty
3. Close and reopen app → subscriptions appear

---

## Why Subscriptions Appear After Restart But Not Immediately

The subscriptions **are** being written to SQLCipher successfully. This is confirmed by them persisting across a restart. On restart, `ViewModel.init` calls `loadSubscriptions(for:)` which reads from SQLCipher → subscriptions appear.

The problem is the **live UI refresh path**, not the persistence path.

---

## Root Cause: Cross-Actor Callback Fires Too Late for the Re-Render Triggered by `dismiss()`

### The callback mechanism (designed for live updates)

`SubscriptionsRepository.saveDittoSubscription` ends with:

```swift
// Notify UI
notifySubscriptionsUpdate()
```

```swift
private func notifySubscriptionsUpdate() {
    onSubscriptionsUpdate?(cachedSubscriptions)
}
```

The callback registered in `MainStudioView.ViewModel.init` is:

```swift
await SubscriptionsRepository.shared.setOnSubscriptionsUpdate { newSubscriptions in
    self.subscriptions = newSubscriptions   // ← runs on SubscriptionsRepository actor thread
}
```

**The problem:** `notifySubscriptionsUpdate()` is called while executing **on the `SubscriptionsRepository` actor**. The callback `{ newSubscriptions in self.subscriptions = newSubscriptions }` therefore runs on the repository actor's executor — **not on `@MainActor`**. This is a cross-actor mutation of a `@MainActor @Observable` property.

`@Observable` mutations from a non-`@MainActor` context schedule a SwiftUI invalidation, but that invalidation is queued asynchronously. It does not execute until the main run loop processes it.

### Why this races with `dismiss()`

After the import loop in `importSubscriptionsFromQR`, execution returns to `@MainActor`. Then `dismiss()` fires. The sheet closes. SwiftUI schedules a re-render of `MainStudioView` due to the sheet dismissal.

**Race condition:** The SwiftUI re-render triggered by `dismiss()` and the SwiftUI invalidation queued by the cross-actor `subscriptions` mutation are both pending on the main run loop. They run in an unspecified order. In practice, the dismissal re-render consistently wins — `MainStudioView` renders before the mutation notification lands, so it shows the stale (empty) `subscriptions` array.

After the mutation notification eventually processes, SwiftUI would re-render `MainStudioView` again — but by then the user already sees an empty list, and depending on SwiftUI version/state, this second render may or may not fire.

### Why the portal import (`ImportSubscriptionsView`) works

The portal import has a critical difference:

```swift
try await viewModel.importSelectedSubscriptions()
try await Task.sleep(nanoseconds: 500_000_000)  // ← 500ms sleep
isPresented = false
```

The **500ms sleep** lets the cross-actor mutation notification process on the main run loop *before* `isPresented = false` triggers the dismissal re-render. By the time `MainStudioView` re-renders, `subscriptions` is already updated.

Our QR import has no such delay — `dismiss()` fires immediately after the loop, causing the race.

### Why `try?` is also a problem

```swift
try? await SubscriptionsRepository.shared.saveDittoSubscription(sub)
```

If `saveDittoSubscription` throws for any reason (e.g., Ditto sync `registerSubscription` failure, SQLCipher constraint, etc.), the error is silently discarded. `cachedSubscriptions` is not updated for that item. `notifySubscriptionsUpdate()` is never called for that item. The loop continues silently.

The portal import uses `try await` — errors propagate and are surfaced to the user. Our QR import should do the same.

---

## Correct Fix

### Two-part solution that mirrors the portal import pattern

**Part 1 — Eliminate the race: read the updated cache on `@MainActor` after the loop**

After all `saveDittoSubscription` calls complete, we are back on `@MainActor` (since `importSubscriptionsFromQR` is in a `@MainActor` class). At this point, `SubscriptionsRepository.cachedSubscriptions` contains all the newly saved subscriptions.

Instead of waiting for the cross-actor callback to propagate, explicitly fetch the current cache and assign it to `subscriptions` **on `@MainActor`** before `dismiss()` fires:

```swift
// After the loop — we are on @MainActor here
let updated = await SubscriptionsRepository.shared.getCachedSubscriptions()
subscriptions = updated   // @MainActor assignment — SwiftUI sees this before dismiss re-render
```

This is identical in effect to what `loadSubscriptions` does at startup, but:
- Does **not** reset `currentDatabaseId`
- Does **not** replace `cachedSubscriptions` (read-only)
- Does **not** lose the `syncSubscription` objects stored in the cache

**Part 2 — Error visibility: `try await` + `do/catch`**

Match the portal import exactly — propagate errors rather than swallowing them.

---

## Files to Modify

| File | Change |
|------|--------|
| `Data/Repositories/SubscriptionsRepository.swift` | Add `getCachedSubscriptions() -> [DittoSubscription]` accessor |
| `Views/MainStudioView.swift` | Fix `importSubscriptionsFromQR` — add `getCachedSubscriptions()` call after loop; change `try?` → `try await` + `do/catch` |

---

## Detailed Changes

### Change 1 — `SubscriptionsRepository.swift`: Add read-only cache accessor

Add after `setOnSubscriptionsUpdate`:

```swift
/// Returns the current in-memory subscription cache without modifying it.
/// Use after `saveDittoSubscription` calls to read the updated state on @MainActor.
func getCachedSubscriptions() -> [DittoSubscription] {
    cachedSubscriptions
}
```

This is a trivial read-only accessor. It does not reset `currentDatabaseId`, does not clear `cachedSubscriptions`, and does not affect `syncSubscription` objects.

---

### Change 2 — `MainStudioView.swift`: Fix `importSubscriptionsFromQR`

**Before:**
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
        onProgress(index + 1, total)
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
        do {
            try await SubscriptionsRepository.shared.saveDittoSubscription(sub)
        } catch {
            appState.setError(error)
        }
        onProgress(index + 1, total)
    }
    // Explicitly refresh subscriptions on @MainActor so SwiftUI sees the update
    // before the sheet dismissal re-render fires. The cross-actor callback
    // (onSubscriptionsUpdate) races with the dismiss re-render; reading the
    // cache here on @MainActor eliminates that race.
    subscriptions = await SubscriptionsRepository.shared.getCachedSubscriptions()
}
```

---

## Why This Fix Is Correct

| | Portal Import | QR Import (broken) | QR Import (fixed) |
|---|---|---|---|
| Error handling | `try await` + propagate | `try?` (silent) | `try await` + `appState.setError` |
| UI refresh mechanism | Cross-actor callback + 500ms sleep | Cross-actor callback only | Explicit `@MainActor` assignment after loop |
| Race with dismiss | Race avoided by 500ms sleep | Race present (instant dismiss) | Race eliminated (subscriptions assigned before dismiss) |
| Subscriptions visible after import | ✅ | ❌ (only after restart) | ✅ |

---

## Verification Checklist

- [ ] Scan QR code → sheet closes → subscriptions appear immediately in the sidebar (no restart needed)
- [ ] If a subscription fails to save, the error appears via `appState.setError` (toast/alert)
- [ ] Scanning the same QR twice → no duplicates, no crash
- [ ] Portal import (`ImportSubscriptionsView`) still works (unaffected by these changes)
- [ ] Build succeeds:
  ```
  xcodebuild -project "Edge Debug Helper.xcodeproj" \
             -scheme "Edge Studio" \
             -destination "platform=macOS,arch=arm64" build
  ```

---

## Out of Scope

- The underlying cross-actor callback design (`onSubscriptionsUpdate`) is a broader issue affecting all subscription updates. The `getCachedSubscriptions()` approach is the targeted fix for QR import specifically. A full fix to the callback would require changing the registration to dispatch on `@MainActor` but that is a larger change with wider impact and is not needed to fix this bug.
- The 500ms delay in the portal import is not replicated here — the explicit `@MainActor` assignment is a more reliable solution than a sleep.
