using System;
using System.Text.Json.Serialization;

namespace EdgeStudio.Models
{
    public record SyncStatusInfo
    {
        [JsonPropertyName("_id")]
        public required string Id { get; init; }

        [JsonPropertyName("is_ditto_server")]
        public bool IsDittoServer { get; init; }

        [JsonPropertyName("documents")]
        public required DocumentsInfo Documents { get; init; }

        [JsonIgnore]
        public string PeerType => IsDittoServer ? "Cloud Server" : "Peer Device";

        [JsonIgnore]
        public bool IsConnected => Documents.SyncSessionStatus == "Connected";

        [JsonIgnore]
        public string ConnectionStatus => IsConnected ? "Connected" : "Not Connected";
    }

    public record DocumentsInfo
    {
        [JsonPropertyName("sync_session_status")]
        public required string SyncSessionStatus { get; init; }

        [JsonPropertyName("synced_up_to_local_commit_id")]
        public long SyncedUpToLocalCommitId { get; init; }

        [JsonPropertyName("last_update_received_time")]
        public long LastUpdateReceivedTimeRaw { get; init; }

        [JsonIgnore]
        public DateTime LastUpdateReceivedTime =>
            DateTimeOffset.FromUnixTimeMilliseconds(LastUpdateReceivedTimeRaw).UtcDateTime;
    }
}
