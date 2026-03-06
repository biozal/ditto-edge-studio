using System.Text.Json.Serialization;

namespace EdgeStudio.Shared.Models;

/// <summary>
/// Represents an active connection for a peer.
/// </summary>
public record PeerConnectionInfo
{
    [JsonPropertyName("connection_type")]
    public required string ConnectionType { get; init; }

    [JsonPropertyName("connection_id")]
    public required string ConnectionId { get; init; }

    [JsonPropertyName("approximate_distance_in_meters")]
    public double? ApproximateDistanceInMeters { get; init; }

    [JsonIgnore]
    public string DisplayName => ConnectionType switch
    {
        "Bluetooth" => "Bluetooth",
        "WiFi" => "Wi-Fi",
        "WebSocket" => "WebSocket",
        "P2PWiFi" => "P2P Wi-Fi",
        _ => ConnectionType
    };

    [JsonIgnore]
    public string IconKind => ConnectionType switch
    {
        "Bluetooth" => "Bluetooth",
        "WiFi" or "P2PWiFi" => "Wifi",
        "WebSocket" => "Cloud",
        _ => "DevicesOther"
    };
}
