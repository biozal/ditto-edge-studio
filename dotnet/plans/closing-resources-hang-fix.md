# Plan: Fix "Closing Database Resources" Dialog Hang

## Status: PENDING APPROVAL

## Problem

When the user clicks the Close button to close an open database, the "Closing database resources…" overlay appears and **never dismisses**. The app is stuck showing the spinner indefinitely.

Screenshot: `screens/dotnet/dotnet-closing-resources.png`

---

## Root Cause Analysis

### The Close Flow

```
EdgeStudioView Close button
  → EdgeStudioViewModel.CloseDatabase()         [RelayCommand, UI thread]
  → WeakReferenceMessenger.Send(CloseDatabaseRequestedMessage)
  → MainWindow.Receive()                        [async void, UI thread]
  → await _viewModel.CloseDatabaseAsync()
      → IsClosingDatabase = true               ← overlay appears
      → await Task.WhenAll(
            _systemRepository.CloseDatabaseAsync(),      // 5-second timeout
            _subscriptionRepository.CloseDatabaseAsync(), // 5-second timeout
            _historyRepository.CloseDatabaseAsync(),      // Task.CompletedTask
            _favoritesRepository.CloseDatabaseAsync()     // Task.CompletedTask
        )
      → await _dittoManager.CloseDatabaseAsync() // 10-second timeout
      → IsClosingDatabase = false              ← overlay should disappear
```

The `ClosingOverlay` is controlled by AXAML data binding: `IsVisible="{Binding IsClosingDatabase}"`. It only goes away when `IsClosingDatabase = false` is set in the `finally` block of `CloseDatabaseAsync()`.

### Identified Bug #1 (Primary): Dispatcher Deadlock via Synchronous `Invoke`

In `SystemRepository.RegisterPeerCardObservers()`, the DQL observer callback contains a **synchronous** `Dispatcher.UIThread.Invoke()` call (line ~150):

```csharp
else  // Not on UI thread
{
    Dispatcher.UIThread.Invoke(() =>   // ← SYNCHRONOUS - blocks calling thread
    {
        var remotePeers = peerCards.Where(p => p.CardType != PeerCardType.Local).ToList();
        foreach (var peer in remotePeers)
            peerCards.Remove(peer);
    });
}
result.Dispose();
return;
```

**Why this hangs the close flow:**

1. `SystemRepository.CloseDatabaseAsync()` is called from the UI thread (via `await Task.WhenAll`).
2. Inside it, `cancelTask = Task.Run(() => observerToCancel.Cancel())` runs on a thread-pool thread.
3. `observerToCancel.Cancel()` is called on the background thread. The Ditto SDK (per common SDK pattern) waits for any in-flight callback to complete before returning from `Cancel()`.
4. If the observer is currently firing (or fires a final callback during `Cancel()`), that callback runs **on the same background thread** or another SDK-internal thread.
5. The callback detects `result.Items.Count == 0` (final empty result), is not on the UI thread, and calls `Dispatcher.UIThread.Invoke()` **synchronously**.
6. `Dispatcher.UIThread.Invoke()` posts a work item to the Avalonia dispatcher queue and **blocks** the calling background thread until the UI thread processes it.
7. Meanwhile, the UI thread is processing async continuations (from the `await Task.WhenAll`). Avalonia's dispatcher processes items in priority order. The async continuation posted by `await Task.WhenAny(cancelTask, Task.Delay(5s))` competes with the `Invoke()` work item.
8. If the observer callback keeps firing (e.g., the SDK fires multiple callbacks while `Sync.Stop()` drains connections), each one adds another `Invoke()` item to the dispatcher queue. These can flood the queue, **indefinitely delaying** the async continuation that would set `IsClosingDatabase = false`.
9. Additionally, if `Cancel()` on the background thread is blocking waiting for the callback to complete, and the callback is waiting for the UI thread, and the UI thread is processing other items from the queue at a different priority than the `Invoke()` item, this creates a priority inversion that prevents the close from completing.

### Identified Bug #2 (Secondary): Observer Not Stopped Before Async Close Begins

The observer is stopped asynchronously inside `Task.WhenAll(...)`. Between `IsClosingDatabase = true` being set and the observer actually stopping (up to 5 seconds), the Ditto SDK is still active and firing callbacks. These callbacks do UI work via `Dispatcher.UIThread.Invoke()` / `InvokeAsync()`, continuing to touch `peerCards` during the close animation.

The observer should be stopped **synchronously** and **first**, before any async cleanup and before the overlay appears.

### Identified Bug #3 (Tertiary): No Reentrance Guard on `CloseDatabaseAsync`

If the user clicks Close multiple times rapidly, `_selectedDatabase != null` passes the guard for all calls (because `_selectedDatabase` is only cleared after all the awaits complete). Multiple concurrent close operations could be initiated, each setting `IsClosingDatabase = true` then `false` out of order.

---

## Key Files

| File | Relevance |
|------|-----------|
| `src/EdgeStudio/ViewModels/MainWindowViewModel.cs` lines 275–311 | `CloseDatabaseAsync()` — the main close method |
| `src/EdgeStudio/Views/MainWindow.axaml` lines 110–130 | `ClosingOverlay` — bound to `IsClosingDatabase` |
| `src/EdgeStudio/Views/MainWindow.axaml.cs` lines 123–136 | `async void Receive()` — triggers the close |
| `src/EdgeStudio.Shared/Data/Repositories/SystemRepository.cs` lines 50–80, 130–226 | Observer with synchronous `Invoke`, `CloseDatabaseAsync()` |
| `src/EdgeStudio.Shared/Data/DittoManager.cs` lines 40–72 | `CloseDatabaseAsync()` — Sync.Stop + Dispose |

---

## Proposed Fix

### Fix 1: Replace `Dispatcher.UIThread.Invoke()` with `InvokeAsync()` in Observer Callback

**File:** `SystemRepository.cs` — inside `RegisterPeerCardObservers()` callback

Change all synchronous `Dispatcher.UIThread.Invoke(...)` calls in the observer callback to `Dispatcher.UIThread.InvokeAsync(...)`. This makes the background thread non-blocking — it fires the UI work and continues without waiting for the UI thread to process it.

**Before:**
```csharp
else
{
    // Not on UI thread - invoke synchronously
    Dispatcher.UIThread.Invoke(() =>
    {
        var remotePeers = peerCards.Where(p => p.CardType != PeerCardType.Local).ToList();
        foreach (var peer in remotePeers)
            peerCards.Remove(peer);
    });
}
result.Dispose();
return;
```

**After:**
```csharp
else
{
    // Not on UI thread - invoke asynchronously to avoid blocking the SDK thread
    Dispatcher.UIThread.InvokeAsync(() =>
    {
        var remotePeers = peerCards.Where(p => p.CardType != PeerCardType.Local).ToList();
        foreach (var peer in remotePeers)
            peerCards.Remove(peer);
    });
}
result.Dispose();
return;
```

> **Why this fixes it:** The SDK background thread (running `Cancel()`) is no longer blocked waiting for the UI thread. `Cancel()` can return, `cancelTask` completes, and the close flow proceeds normally.

### Fix 2: Stop the Observer Synchronously Before Starting Async Close

**File:** `MainWindowViewModel.CloseDatabaseAsync()`

Call `_systemRepository.CloseSelectedDatabase()` synchronously **before** the `await Task.WhenAll(...)` line. This cancels the observer before the async chain starts, preventing any new callbacks from firing during the close.

```csharp
public async Task CloseDatabaseAsync()
{
    if (_selectedDatabase == null)
        return;

    IsClosingDatabase = true;

    try
    {
        _logCaptureService.StopCapture();

        // Stop observers synchronously first — prevents SDK callbacks from
        // firing during the async close and competing for the UI dispatcher.
        _systemRepository.CloseSelectedDatabase();
        _subscriptionRepository.CloseSelectedDatabase();

        // Now do the async cleanup (flush/dispose on background threads)
        await Task.WhenAll(
            _systemRepository.CloseDatabaseAsync(),
            _subscriptionRepository.CloseDatabaseAsync(),
            _historyRepository.CloseDatabaseAsync(),
            _favoritesRepository.CloseDatabaseAsync()
        );

        await _dittoManager.CloseDatabaseAsync();

        _selectedDatabase = null;
        OnPropertyChanged(nameof(SelectedDatabase));
        OnPropertyChanged(nameof(HasSelectedDatabase));
    }
    catch (Exception ex)
    {
        ShowError($"Error closing database: {ex.Message}");
    }
    finally
    {
        IsClosingDatabase = false;
    }
}
```

> **Note:** `CloseSelectedDatabase()` is already idempotent in both `SystemRepository` and `SqliteSubscriptionRepository` — calling it before `CloseDatabaseAsync()` is safe. `CloseDatabaseAsync()` handles the null case and returns early.

### Fix 3: Add Reentrance Guard

**File:** `MainWindowViewModel.CloseDatabaseAsync()`

Add an `_isClosingDatabase` field guard at the top of the method to prevent concurrent close operations:

```csharp
private bool _isCloseInProgress;

public async Task CloseDatabaseAsync()
{
    if (_selectedDatabase == null || _isCloseInProgress)
        return;

    _isCloseInProgress = true;
    IsClosingDatabase = true;

    try
    {
        // ... close logic ...
    }
    finally
    {
        _isCloseInProgress = false;
        IsClosingDatabase = false;
    }
}
```

### Fix 4 (Optional): Add Null Guard in Observer Callback

**File:** `SystemRepository.cs` — observer callback

Add a guard to skip processing if the observer has been cancelled (indicated by `_syncStatusObserver` being null):

```csharp
_syncStatusObserver = ditto.Store.RegisterObserver(
    "SELECT * FROM system:data_sync_info ORDER BY documents.last_update_received_time desc",
    (result) =>
    {
        // Guard: skip processing if observer has been cancelled
        if (_syncStatusObserver == null)
        {
            result.Dispose();
            return;
        }
        // ... rest of callback ...
    });
```

---

## Implementation Order

1. **Fix 1** — Replace `Dispatcher.UIThread.Invoke()` with `InvokeAsync()` in `SystemRepository` observer callback (primary fix, addresses root cause)
2. **Fix 2** — Synchronously stop observers before async close in `MainWindowViewModel.CloseDatabaseAsync()`
3. **Fix 3** — Add reentrance guard to `CloseDatabaseAsync()`
4. **Fix 4** — Add null guard in observer callback (defensive, optional)

Fixes 1 and 2 together should fully resolve the hang. Fixes 3 and 4 are defensive improvements.

---

## Testing

After implementing the fixes:

1. Open a database in Edge Studio (.NET)
2. Wait a few seconds for the sync status observer to start firing
3. Click the close button (×) in the top toolbar
4. **Expected:** "Closing database resources…" overlay appears, then disappears within 1–2 seconds
5. **Expected:** Returns to the database list view
6. Repeat multiple times quickly (test reentrance guard)
7. Test with Bluetooth/LAN active (more observers firing during close)

---

## Build Command

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```
