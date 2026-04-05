using System;
using System.Text.Json.Serialization;

namespace EdgeStudio.Shared.Models
{
    /// <summary>
    /// Represents a user-defined observer definition with a name and DQL query.
    /// Observer definitions are persisted to SQLite. Active DittoStoreObserver
    /// references are runtime-only and must be re-activated each session.
    /// </summary>
    public record DittoDatabaseObserver(
        [property: JsonPropertyName("_id")] string Id,
        [property: JsonPropertyName("name")] string Name,
        [property: JsonPropertyName("query")] string Query)
        : IIdModel
    {
        /// <summary>
        /// Runtime-only flag indicating whether this observer is currently active.
        /// Not persisted to SQLite.
        /// </summary>
        [JsonIgnore]
        public bool IsActive { get; init; } = false;
    }
}
