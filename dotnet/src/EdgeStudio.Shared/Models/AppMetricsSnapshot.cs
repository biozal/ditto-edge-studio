using System;

namespace EdgeStudio.Shared.Models;

public record CollectionStorageInfo(
    string CollectionName,
    int DocumentCount,
    long EstimatedBytes)
{
    public string EstimatedBytesFormatted => FormatBytes(EstimatedBytes);
    public string DocumentCountFormatted => $"{DocumentCount} docs";
    private static string FormatBytes(long bytes) => bytes switch
    {
        < 1024 => $"{bytes} B",
        < 1024 * 1024 => $"{bytes / 1024.0:F1} KB",
        _ => $"{bytes / (1024.0 * 1024):F1} MB"
    };
}

public record AppMetricsSnapshot(
    DateTimeOffset CapturedAt,
    // Process
    long ResidentMemoryBytes,
    long VirtualMemoryBytes,
    double CpuTimeSeconds,
    int OpenHandleCount,
    TimeSpan ProcessUptime,
    // Queries
    int TotalQueryCount,
    double AvgQueryLatencyMs,
    double? LastQueryLatencyMs,
    // Storage
    long StoreBytes,
    long ReplicationBytes,
    long AttachmentsBytes,
    long AuthBytes,
    long WalShmBytes,
    long LogsBytes,
    long OtherBytes,
    System.Collections.Generic.IReadOnlyList<CollectionStorageInfo> CollectionBreakdown)
{
    private static string FormatBytes(long bytes) => bytes switch
    {
        0 => "0 B",
        < 1024 => $"{bytes} B",
        < 1024 * 1024 => $"{bytes / 1024.0:F1} KB",
        _ => $"{bytes / (1024.0 * 1024):F1} MB"
    };

    private static string FormatMs(double ms) => ms switch
    {
        < 1 => "< 1 ms",
        < 1000 => $"{ms:F1} ms",
        _ => $"{ms / 1000:F2} s"
    };

    public string ResidentMemoryFormatted => FormatBytes(ResidentMemoryBytes);
    public string VirtualMemoryFormatted => FormatBytes(VirtualMemoryBytes);
    public string CpuTimeFormatted => $"{CpuTimeSeconds:F2} s";
    public string UptimeFormatted
    {
        get
        {
            var ts = ProcessUptime;
            if (ts.TotalDays >= 1) return $"{(int)ts.TotalDays}d {ts.Hours}h";
            if (ts.TotalHours >= 1) return $"{(int)ts.TotalHours}h {ts.Minutes}m";
            if (ts.TotalMinutes >= 1) return $"{(int)ts.TotalMinutes}m {ts.Seconds}s";
            return $"{ts.Seconds}s";
        }
    }
    public string AvgLatencyFormatted => TotalQueryCount > 0 ? FormatMs(AvgQueryLatencyMs) : "—";
    public string LastLatencyFormatted => LastQueryLatencyMs.HasValue ? FormatMs(LastQueryLatencyMs.Value) : "—";
    public string StoreBytesFormatted => FormatBytes(StoreBytes);
    public string ReplicationBytesFormatted => FormatBytes(ReplicationBytes);
    public string AttachmentsBytesFormatted => FormatBytes(AttachmentsBytes);
    public string AuthBytesFormatted => FormatBytes(AuthBytes);
    public string WalShmBytesFormatted => FormatBytes(WalShmBytes);
    public string LogsBytesFormatted => FormatBytes(LogsBytes);
    public string OtherBytesFormatted => FormatBytes(OtherBytes);
    public long TotalStorageBytes => StoreBytes + ReplicationBytes + AttachmentsBytes + AuthBytes + WalShmBytes + LogsBytes + OtherBytes;
    public string TotalStorageBytesFormatted => FormatBytes(TotalStorageBytes);
    public bool HasCollectionBreakdown => CollectionBreakdown.Count > 0;
    public string CollectionBreakdownHeader => $"COLLECTIONS ({CollectionBreakdown.Count})";
}
