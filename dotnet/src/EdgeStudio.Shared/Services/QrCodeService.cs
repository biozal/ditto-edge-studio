using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using EdgeStudio.Shared.Models;

namespace EdgeStudio.Shared.Services
{
    public sealed class QrCodeService : IQrCodeService
    {
        private const string Prefix = "EDS2:";
        private const int MaxPayloadBytes = 2200;

        private static readonly JsonSerializerOptions JsonOptions = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
        };

        public string Encode(DittoDatabaseConfig config, IEnumerable<string> favoriteQueries)
        {
            var favorites = favoriteQueries.Select(q => new FavoriteEntry(q)).ToList();

            while (true)
            {
                var payload = new QrPayload(2, config, favorites);
                var json = JsonSerializer.Serialize(payload, JsonOptions);
                var compressed = Compress(Encoding.UTF8.GetBytes(json));
                var result = Prefix + Convert.ToBase64String(compressed);

                if (result.Length <= MaxPayloadBytes || favorites.Count == 0)
                    return result;

                // Drop oldest favorite (first in list) and retry
                favorites.RemoveAt(0);
            }
        }

        public (DittoDatabaseConfig config, List<string> favorites)? Decode(string payload)
        {
            try
            {
                string json;
                if (payload.StartsWith(Prefix, StringComparison.Ordinal))
                {
                    var base64 = payload[Prefix.Length..];
                    var compressed = Convert.FromBase64String(base64);
                    var decompressed = Decompress(compressed);
                    json = Encoding.UTF8.GetString(decompressed);
                }
                else
                {
                    // Legacy v1 or plain JSON
                    json = payload;
                }

                var qrPayload = JsonSerializer.Deserialize<QrPayload>(json, JsonOptions);
                if (qrPayload?.Config != null)
                {
                    var favs = qrPayload.Favorites?.Select(f => f.Q).Where(q => q != null).Cast<string>().ToList()
                               ?? new List<string>();
                    return (qrPayload.Config, favs);
                }

                // Fallback: try to parse as a bare DittoDatabaseConfig
                var bareConfig = JsonSerializer.Deserialize<DittoDatabaseConfig>(json, JsonOptions);
                if (bareConfig != null)
                    return (bareConfig, new List<string>());

                return null;
            }
            catch
            {
                return null;
            }
        }

        private static byte[] Compress(byte[] data)
        {
            using var output = new MemoryStream();
            using (var deflate = new DeflateStream(output, CompressionLevel.Optimal))
                deflate.Write(data);
            return output.ToArray();
        }

        private static byte[] Decompress(byte[] data)
        {
            using var input = new MemoryStream(data);
            using var deflate = new DeflateStream(input, CompressionMode.Decompress);
            using var output = new MemoryStream();
            deflate.CopyTo(output);
            return output.ToArray();
        }

        private record QrPayload(
            [property: JsonPropertyName("version")] int Version,
            [property: JsonPropertyName("config")] DittoDatabaseConfig? Config,
            [property: JsonPropertyName("favorites")] List<FavoriteEntry>? Favorites);

        private record FavoriteEntry(
            [property: JsonPropertyName("q")] string Q);
    }
}
