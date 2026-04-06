using System.Collections.Generic;
using System.Text.Json;

namespace EdgeStudio.Shared.Models;

/// <summary>
/// Represents a parsed attachment token found in a document field.
/// </summary>
public class AttachmentInfo
{
    public string Id { get; init; } = string.Empty;
    public string FieldName { get; init; } = string.Empty;
    public long Length { get; init; }
    public Dictionary<string, string> Metadata { get; init; } = new();

    public string FormattedSize => FormatBytes(Length);

    public string? MimeType =>
        Metadata.GetValueOrDefault("mimeType") ??
        Metadata.GetValueOrDefault("mime_type") ??
        Metadata.GetValueOrDefault("type");

    public string? FileName =>
        Metadata.GetValueOrDefault("name") ??
        Metadata.GetValueOrDefault("fileName") ??
        Metadata.GetValueOrDefault("file_name");

    public bool IsImage => MimeType?.StartsWith("image/") == true;

    /// <summary>
    /// Scans a JSON document string for fields that look like attachment tokens.
    /// An attachment token has the shape: { "id": string, "len": number, "metadata": object }
    /// </summary>
    public static List<AttachmentInfo> DetectTokens(string jsonString)
    {
        var results = new List<AttachmentInfo>();
        try
        {
            using var doc = JsonDocument.Parse(jsonString);
            foreach (var prop in doc.RootElement.EnumerateObject())
            {
                if (prop.Value.ValueKind != JsonValueKind.Object)
                    continue;

                if (!prop.Value.TryGetProperty("id", out var idProp) ||
                    idProp.ValueKind != JsonValueKind.String)
                    continue;

                if (!prop.Value.TryGetProperty("len", out var lenProp) ||
                    lenProp.ValueKind != JsonValueKind.Number)
                    continue;

                if (!prop.Value.TryGetProperty("metadata", out var metaProp) ||
                    metaProp.ValueKind != JsonValueKind.Object)
                    continue;

                var metadata = new Dictionary<string, string>();
                foreach (var metaField in metaProp.EnumerateObject())
                {
                    metadata[metaField.Name] = metaField.Value.ToString();
                }

                results.Add(new AttachmentInfo
                {
                    Id = idProp.GetString() ?? string.Empty,
                    FieldName = prop.Name,
                    Length = lenProp.GetInt64(),
                    Metadata = metadata
                });
            }
        }
        catch
        {
            // Not valid JSON or unexpected structure — return empty
        }

        return results;
    }

    private static string FormatBytes(long bytes)
    {
        string[] suffixes = ["B", "KB", "MB", "GB"];
        var order = 0;
        double size = bytes;
        while (size >= 1024 && order < suffixes.Length - 1)
        {
            order++;
            size /= 1024;
        }
        return $"{size:0.#} {suffixes[order]}";
    }
}
