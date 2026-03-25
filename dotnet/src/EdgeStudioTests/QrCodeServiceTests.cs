using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;
using FluentAssertions;
using System;
using System.Collections.Generic;
using System.Linq;
using Xunit;

namespace EdgeStudioTests
{
    /// <summary>
    /// Unit tests for QrCodeService: EDS2 encode/decode, compression, and edge cases.
    /// </summary>
    public class QrCodeServiceTests
    {
        private readonly QrCodeService _service = new QrCodeService();

        private static DittoDatabaseConfig MakeConfig(string id = "test-id") =>
            new DittoDatabaseConfig(
                Id: id,
                Name: "Test DB",
                DatabaseId: "db-" + id,
                AuthToken: "tok-" + id,
                AuthUrl: "https://auth.example.com",
                HttpApiUrl: "https://api.example.com",
                HttpApiKey: "key-" + id,
                Mode: "server",
                AllowUntrustedCerts: false,
                WebsocketUrl: "wss://ws.example.com",
                IsStrictModeEnabled: true
            );

        [Fact]
        public void Encode_ProducesEDS2Prefix()
        {
            var config = MakeConfig();
            var result = _service.Encode(config, Array.Empty<string>());

            result.Should().StartWith("EDS2:");
        }

        [Fact]
        public void Encode_ThenDecode_RoundtripsConfig()
        {
            var config = MakeConfig();
            var payload = _service.Encode(config, Array.Empty<string>());

            var decoded = _service.Decode(payload);

            decoded.Should().NotBeNull();
            var (decodedConfig, _) = decoded!.Value;
            decodedConfig.Id.Should().Be(config.Id);
            decodedConfig.Name.Should().Be(config.Name);
            decodedConfig.DatabaseId.Should().Be(config.DatabaseId);
            decodedConfig.AuthToken.Should().Be(config.AuthToken);
            decodedConfig.AuthUrl.Should().Be(config.AuthUrl);
            decodedConfig.HttpApiUrl.Should().Be(config.HttpApiUrl);
            decodedConfig.HttpApiKey.Should().Be(config.HttpApiKey);
            decodedConfig.Mode.Should().Be(config.Mode);
            decodedConfig.AllowUntrustedCerts.Should().Be(config.AllowUntrustedCerts);
            decodedConfig.WebsocketUrl.Should().Be(config.WebsocketUrl);
            decodedConfig.IsStrictModeEnabled.Should().Be(config.IsStrictModeEnabled);
        }

        [Fact]
        public void Encode_ThenDecode_RoundtripsFavorites()
        {
            var config = MakeConfig();
            var favorites = new[] { "SELECT * FROM docs", "SELECT _id FROM users" };
            var payload = _service.Encode(config, favorites);

            var decoded = _service.Decode(payload);

            decoded.Should().NotBeNull();
            var (_, decodedFavs) = decoded!.Value;
            decodedFavs.Should().BeEquivalentTo(favorites);
        }

        [Fact]
        public void Encode_TruncatesFavoritesWhenOver2200Bytes()
        {
            var config = MakeConfig();
            // Create many large favorites that would exceed the 2200-byte limit
            var largeFavorites = Enumerable.Range(1, 50)
                .Select(i => $"SELECT * FROM collection_{i} WHERE field = 'value_{new string('x', 50)}'")
                .ToList();

            var payload = _service.Encode(config, largeFavorites);

            payload.Length.Should().BeLessThanOrEqualTo(2200);
            payload.Should().StartWith("EDS2:");
        }

        [Fact]
        public void Decode_V1PlainJson_IsSupported()
        {
            // v1 format: plain uncompressed JSON with the config wrapped in a QrPayload structure
            var json = """
                {
                    "version": 1,
                    "config": {
                        "_id": "v1-id",
                        "name": "V1 DB",
                        "databaseId": "db-v1",
                        "token": "tok-v1",
                        "authUrl": "https://auth.example.com",
                        "httpApiUrl": "",
                        "httpApiKey": "",
                        "mode": "server",
                        "allowUntrustedCerts": false
                    },
                    "favorites": []
                }
                """;

            var decoded = _service.Decode(json);

            decoded.Should().NotBeNull();
            var (config, _) = decoded!.Value;
            config.Id.Should().Be("v1-id");
            config.Name.Should().Be("V1 DB");
            config.Mode.Should().Be("server");
        }

        [Fact]
        public void Decode_InvalidPayload_ReturnsNull()
        {
            var decoded = _service.Decode("not-a-valid-payload-!!garbage!!");

            decoded.Should().BeNull();
        }

        [Fact]
        public void Decode_MissingFields_UsesDefaults()
        {
            // Partial JSON — only required fields, no WebsocketUrl or IsStrictModeEnabled
            var json = """
                {
                    "version": 1,
                    "config": {
                        "_id": "partial-id",
                        "name": "Partial DB",
                        "databaseId": "db-partial",
                        "token": "tok",
                        "authUrl": "https://auth.example.com",
                        "httpApiUrl": "",
                        "httpApiKey": "",
                        "mode": "server",
                        "allowUntrustedCerts": false
                    }
                }
                """;

            var decoded = _service.Decode(json);

            decoded.Should().NotBeNull();
            var (config, favs) = decoded!.Value;
            config.WebsocketUrl.Should().Be("");
            config.IsStrictModeEnabled.Should().BeFalse();
            favs.Should().BeEmpty();
        }
    }
}
