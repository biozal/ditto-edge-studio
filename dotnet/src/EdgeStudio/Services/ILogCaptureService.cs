using System.Collections.Generic;
using EdgeStudio.Models.Logging;

namespace EdgeStudio.Services;

/// <summary>
/// Owns the transport condition subscription for the lifetime of the open database.
/// Start/Stop is driven by database open/close, not by Logging screen visibility,
/// so events are never missed while the user is on another screen.
/// </summary>
public interface ILogCaptureService
{
    IReadOnlyList<LogEntry> TransportConditionEntries { get; }
    bool HasNewTransportEntries { get; }
    void StartCapture(DittoSDK.Ditto ditto);
    void StopCapture();
    void ClearTransportConditionEntries();
    void AcknowledgeNewEntries();

    IReadOnlyList<LogEntry> ConnectionRequestEntries { get; }
    bool HasNewConnectionRequestEntries { get; }
    void ClearConnectionRequestEntries();
    void AcknowledgeConnectionRequestEntries();
}
