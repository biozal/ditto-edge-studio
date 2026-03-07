using System;
using System.Collections.Generic;
using DittoSDK;
using EdgeStudio.Models.Logging;

namespace EdgeStudio.Services;

/// <summary>
/// Intercepts Ditto SDK log messages via DittoLogger.CustomLogCallback
/// and buffers them for display in the Logging view.
///
/// Performance design:
/// - Uses LinkedList for O(1) add-to-back and remove-from-front (no array shifts).
/// - No event is fired per message; consumers poll via HasNewEntries + GetSnapshot().
/// - The UI thread is never touched from the log callback.
/// - Only Cleared fires an event so the UI can respond immediately to user-initiated clears.
/// </summary>
public sealed class DittoLogCaptureService : IDisposable
{
    private const int MaxEntries = 2000;

    private readonly object _lock = new();
    private readonly LinkedList<LogEntry> _entries = new();
    private volatile bool _hasNewEntries;
    private bool _isCapturing;
    private bool _disposed;

    /// <summary>
    /// True when new entries have been added since the last call to GetSnapshot().
    /// Volatile read — safe to check from any thread without taking the lock.
    /// </summary>
    public bool HasNewEntries => _hasNewEntries;

    /// <summary>
    /// Raised only when the buffer is explicitly cleared by the user.
    /// Not raised per log message.
    /// </summary>
    public event EventHandler? Cleared;

    public void StartCapture(string minimumLevel = "verbose")
    {
        if (_isCapturing) return;
        try
        {
            DittoLogger.MinimumLogLevel = minimumLevel switch
            {
                "error"   => DittoLogLevel.Error,
                "warning" => DittoLogLevel.Warning,
                "debug"   => DittoLogLevel.Debug,
                "verbose" => DittoLogLevel.Verbose,
                _         => DittoLogLevel.Info,
            };
            DittoLogger.CustomLogCallback = OnDittoLog;
            _isCapturing = true;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[DittoLogCaptureService] Failed to start capture: {ex.Message}");
        }
    }

    public void StopCapture()
    {
        if (!_isCapturing) return;
        try { DittoLogger.CustomLogCallback = null; }
        catch { /* ignore */ }
        _isCapturing = false;
    }

    /// <summary>
    /// Returns a snapshot of current entries and resets the dirty flag.
    /// Safe to call from any thread; holds the lock only during the copy.
    /// </summary>
    public List<LogEntry> GetSnapshot()
    {
        lock (_lock)
        {
            _hasNewEntries = false;
            return new List<LogEntry>(_entries);
        }
    }

    public int Count
    {
        get { lock (_lock) { return _entries.Count; } }
    }

    public void Clear()
    {
        lock (_lock)
        {
            _entries.Clear();
            _hasNewEntries = false;
        }
        Cleared?.Invoke(this, EventArgs.Empty);
    }

    private void OnDittoLog(DittoLogLevel level, string message)
    {
        var appLevel = level switch
        {
            DittoLogLevel.Error   => AppLogLevel.Error,
            DittoLogLevel.Warning => AppLogLevel.Warning,
            DittoLogLevel.Debug   => AppLogLevel.Debug,
            DittoLogLevel.Verbose => AppLogLevel.Verbose,
            _                     => AppLogLevel.Info,
        };

        var safeMessage = message ?? string.Empty;
        var entry = new LogEntry(
            Id: Guid.NewGuid(),
            Timestamp: DateTimeOffset.Now,
            Level: appLevel,
            Message: safeMessage,
            Component: LogEntry.DetectComponent(safeMessage),
            Source: LogEntrySource.DittoSDK,
            RawLine: safeMessage
        );

        lock (_lock)
        {
            _entries.AddLast(entry);        // O(1)
            if (_entries.Count > MaxEntries)
                _entries.RemoveFirst();     // O(1) — no array shift
        }

        // Signal dirty without touching the UI thread.
        _hasNewEntries = true;
    }

    public void Dispose()
    {
        if (!_disposed)
        {
            StopCapture();
            _disposed = true;
        }
    }
}
