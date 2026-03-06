
using System.Text.Json.Serialization;
namespace EdgeStudio.Shared.Models
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
    [property: JsonPropertyName("allowUntrustedCerts")] bool AllowUntrustedCerts,
    [property: JsonPropertyName("isBluetoothLeEnabled")] bool IsBluetoothLeEnabled = true,
    [property: JsonPropertyName("isLanEnabled")]         bool IsLanEnabled = true,
    [property: JsonPropertyName("isAwdlEnabled")]        bool IsAwdlEnabled = true,
    [property: JsonPropertyName("isCloudSyncEnabled")]   bool IsCloudSyncEnabled = true,
    [property: JsonPropertyName("isWifiAwareEnabled")]   bool IsWifiAwareEnabled = false,
    [property: JsonPropertyName("logLevel")]             string LogLevel = "info",
    [property: JsonPropertyName("secretKey")]            string SharedKey = "")
        : IIdModel
    {
    }
}
