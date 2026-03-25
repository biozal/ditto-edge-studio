using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace EdgeStudio.Shared.Models
{
    /// <summary>
    /// Represents metadata about a Ditto database collection.
    /// </summary>
    public class CollectionInfo : IIdModel
    {
        /// <summary>
        /// Collection name (same as Id).
        /// </summary>
        [JsonPropertyName("_id")]
        public string Id { get; init; } = string.Empty;

        /// <summary>
        /// Display name for the collection.
        /// </summary>
        [JsonPropertyName("name")]
        public string Name { get; init; } = string.Empty;

        /// <summary>
        /// Number of documents in the collection.
        /// </summary>
        [JsonPropertyName("documentCount")]
        public int DocumentCount { get; init; }

        /// <summary>
        /// Last modified timestamp.
        /// </summary>
        [JsonPropertyName("lastModified")]
        public DateTime LastModified { get; init; }

        /// <summary>
        /// Indexes defined on this collection.
        /// </summary>
        public IReadOnlyList<IndexInfo> Indexes { get; init; } = [];
    }
}
