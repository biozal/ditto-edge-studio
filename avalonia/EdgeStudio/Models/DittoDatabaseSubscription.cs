using DittoSDK;
using System.Text.Json.Serialization;

namespace EdgeStudio.Models
{
    public record DittoDatabaseSubscription(
        [property: JsonPropertyName("_id")] string Id,
        [property: JsonPropertyName("name")] string Name,
        [property: JsonPropertyName("query")] string Query)
    {
    }
}
