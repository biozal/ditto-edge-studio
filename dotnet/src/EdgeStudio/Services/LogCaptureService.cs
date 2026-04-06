using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using DittoSDK.Transport;
using EdgeStudio.Models.Logging;

namespace EdgeStudio.Services;

/// <summary>
/// Singleton implementation of <see cref="ILogCaptureService"/>.
/// Subscribes to transport condition events and connection request events
/// for the duration of a database session and caches them for display in
/// the Logging view at any time.
/// </summary>
public sealed class LogCaptureService : ILogCaptureService
{
    private readonly List<LogEntry> _transportEntries = new();
    private readonly List<LogEntry> _connectionRequestEntries = new();
    private readonly object _lock = new();
    private DittoSDK.Ditto? _ditto;
    private volatile bool _hasNewTransportEntries;
    private volatile bool _hasNewConnectionRequestEntries;

    // ── Transport Conditions ────────────────────────────────────────────────

    public IReadOnlyList<LogEntry> TransportConditionEntries
    {
        get { lock (_lock) { return _transportEntries.ToArray(); } }
    }

    public bool HasNewTransportEntries => _hasNewTransportEntries;

    public void ClearTransportConditionEntries()
    {
        lock (_lock) { _transportEntries.Clear(); }
        _hasNewTransportEntries = false;
    }

    public void AcknowledgeNewEntries() => _hasNewTransportEntries = false;

    // ── Connection Requests ─────────────────────────────────────────────────

    public IReadOnlyList<LogEntry> ConnectionRequestEntries
    {
        get { lock (_lock) { return _connectionRequestEntries.ToArray(); } }
    }

    public bool HasNewConnectionRequestEntries => _hasNewConnectionRequestEntries;

    public void ClearConnectionRequestEntries()
    {
        lock (_lock) { _connectionRequestEntries.Clear(); }
        _hasNewConnectionRequestEntries = false;
    }

    public void AcknowledgeConnectionRequestEntries() => _hasNewConnectionRequestEntries = false;

    // ── Lifecycle ───────────────────────────────────────────────────────────

    public void StartCapture(DittoSDK.Ditto ditto)
    {
        StopCapture();
        _ditto = ditto;
        ditto.DittoTransportConditionChanged += OnTransportConditionChanged;
        ditto.Presence.ConnectionRequestHandler = OnConnectionRequestReceived;
    }

    public void StopCapture()
    {
        if (_ditto == null) return;
        try
        {
            _ditto.DittoTransportConditionChanged -= OnTransportConditionChanged;
            _ditto.Presence.ConnectionRequestHandler = null;
        }
        catch { /* ignore if already disposed */ }
        _ditto = null;
    }

    // ── Event/handler implementations ───────────────────────────────────────

    private void OnTransportConditionChanged(object? sender, DittoTransportConditionChangedEventArgs e)
    {
        var msg = $"Transport: {e.Source} → {e.Condition}";
        var entry = new LogEntry(
            Id:        Guid.NewGuid(),
            Timestamp: DateTimeOffset.Now,
            Level:     AppLogLevel.Info,
            Message:   msg,
            Component: LogComponent.Transport,
            Source:    LogEntrySource.TransportConditions,
            RawLine:   msg
        );
        lock (_lock) { _transportEntries.Add(entry); }
        _hasNewTransportEntries = true;
    }

    private Task<DittoConnectionRequestAuthorization> OnConnectionRequestReceived(DittoConnectionRequest request)
    {
        var identity = string.IsNullOrEmpty(request.IdentityServiceMetadataJsonString) ||
                       request.IdentityServiceMetadataJsonString == "{}"
            ? "none"
            : request.IdentityServiceMetadataJsonString;
        var meta = string.IsNullOrEmpty(request.PeerMetadataJsonString) ||
                   request.PeerMetadataJsonString == "{}"
            ? "none"
            : request.PeerMetadataJsonString;
        var msg = $"Connection Request | type={request.ConnectionType} | key={request.PeerKey}" +
                  $" | identity={identity} | meta={meta}";
        var entry = new LogEntry(
            Id:        Guid.NewGuid(),
            Timestamp: DateTimeOffset.Now,
            Level:     AppLogLevel.Info,
            Message:   msg,
            Component: LogComponent.Auth,
            Source:    LogEntrySource.ConnectionRequests,
            RawLine:   msg
        );
        lock (_lock) { _connectionRequestEntries.Add(entry); }
        _hasNewConnectionRequestEntries = true;
        return Task.FromResult(DittoConnectionRequestAuthorization.Allow);
    }
}
