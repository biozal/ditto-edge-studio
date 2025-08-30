using System.Text.Json.Serialization;

namespace EdgeStudio.Models
{
    public record DittoDatabaseConfig(
    [property: JsonPropertyName("_id")] string Id,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("databaseId")] string DatabaseId,
    [property: JsonPropertyName("authToken")] string AuthToken,
    [property: JsonPropertyName("authURL")] string AuthUrl,
    [property: JsonPropertyName("httpApiUrl")] string HttpApiUrl,
    [property: JsonPropertyName("httpApiKey")] string HttpApiKey,
    [property: JsonPropertyName("mode")] string Mode,
    [property: JsonPropertyName("allowUntrustedCerts")] bool AllowUntrustedCerts)
    {
    }
}
