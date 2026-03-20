using System.Text.Json.Serialization;

namespace EdgeStudio.Shared.Models
{
    public interface IIdModel
    {
        /// <summary>
        /// Unique identifier for the query history entry (maps to _id in Ditto).
        /// </summary>
        [JsonPropertyName("_id")]
        public string Id { get; init; }
    }
}
