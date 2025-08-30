using System.Text.Json.Serialization;

namespace EdgeStudio.Models
{
    public record DittoDatabaseConfig(
    [property: JsonPropertyName("_id")] string Id,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("databaseId")] string DatabaseId,
    [property: JsonPropertyName("authToken")] string AuthToken,
    [property: JsonPropertyName("authURL")] string AuthUrl,
    [property: JsonPropertyName("websocketUrl")] string? WebsocketUrl,
    [property: JsonPropertyName("httpApiUrl")] string HttpApiUrl,
    [property: JsonPropertyName("httpApiKey")] string HttpApiKey,
    [property: JsonPropertyName("mode")] string Mode,
    [property: JsonPropertyName("allowUntrustedCerts")] bool AllowUntrustedCerts)
    {
        public DittoDatabaseConfig(
            string Id,
            string Name,
            string DatabaseId,
            string AuthToken,
            string AuthUrl,
            string HttpApiUrl,
            string HttpApiKey,
            string Mode,
            bool AllowUntrustedCerts) 
            : this(Id, Name, DatabaseId, AuthToken, AuthUrl, null, HttpApiUrl, HttpApiKey, Mode, AllowUntrustedCerts)
        {
        }
    }
}
