using System.Text.Json.Serialization;

namespace EdgeStudio.Shared.Models
{
    public record DittoDatabaseSubscription(
        [property: JsonPropertyName("_id")] string Id,
        [property: JsonPropertyName("name")] string Name,
        [property: JsonPropertyName("query")] string Query)
        : IIdModel
    {
    }
}
