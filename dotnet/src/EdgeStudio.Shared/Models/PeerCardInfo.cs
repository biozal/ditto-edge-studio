using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace EdgeStudio.Shared.Models;

/// <summary>
/// Unified immutable model combining DQL sync status with Presence Graph data.
/// Supports three card types: Local, Remote, and Server.
/// </summary>
public record PeerCardInfo : IIdModel
{
    // === Common Properties ===
    [JsonPropertyName("_id")]
    public required string Id { get; init; }

    [JsonIgnore]
    public required PeerCardType CardType { get; init; }

    // === Local Peer Properties ===
    [JsonPropertyName("device_name")]
    public string? DeviceName { get; init; }

    [JsonIgnore]
    public string? SdkLanguage { get; init; }

    [JsonPropertyName("sdk_platform")]
    public string? SdkPlatform { get; init; }

    [JsonPropertyName("sdk_version")]
    public string? SdkVersion { get; init; }

    // === Remote Peer Properties ===
    [JsonPropertyName("os")]
    public string? OperatingSystem { get; init; }

    [JsonPropertyName("ditto_address")]
    public string? DittoAddress { get; init; }

    [JsonIgnore]
    public List<PeerConnectionInfo>? ActiveConnections { get; init; }

    // === Remote + Server Properties ===
    [JsonPropertyName("commit_id")]
    public long? CommitId { get; init; }

    [JsonPropertyName("last_updated")]
    public DateTime? LastUpdated { get; init; }

    [JsonPropertyName("sync_session_status")]
    public string? SyncSessionStatus { get; init; }

    // === Server Properties ===
    [JsonPropertyName("is_ditto_server")]
    public bool IsDittoServer { get; init; }

    // === Computed Properties ===
    [JsonIgnore]
    public string DisplayName => CardType switch
    {
        PeerCardType.Local => DeviceName ?? "Local Peer",
        PeerCardType.Remote => DeviceName ?? "Remote Peer",
        PeerCardType.Server => "Server",
        _ => "Unknown Peer"
    };

    [JsonIgnore]
    public bool IsConnected => SyncSessionStatus == "Connected";

    [JsonIgnore]
    public string ConnectionStatus => IsConnected ? "Connected" : "Not Connected";

    [JsonIgnore]
    public string LastUpdatedFormatted => LastUpdated.HasValue
        ? LastUpdated.Value.ToString("M/d/yy, h:mm:ss tt")
        : "Never";

    [JsonIgnore]
    public string OsIconKind => OperatingSystem?.ToLowerInvariant() switch
    {
        var os when os?.Contains("windows") == true => "MicrosoftWindows",
        var os when os?.Contains("macos") == true || os?.Contains("darwin") == true => "Apple",
        var os when os?.Contains("linux") == true => "Linux",
        var os when os?.Contains("ios") == true => "AppleIos",
        var os when os?.Contains("android") == true => "Android",
        _ => "DevicesOther"
    };
}
