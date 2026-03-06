using System.Diagnostics.CodeAnalysis;
using System.Text.Json.Serialization;

namespace EdgeStudio.Shared.Models;

/// <summary>
/// Represents a query history or favorite entry stored in Ditto.
/// Immutable record type for tracking executed queries with timestamps.
/// </summary>
public record QueryHistory
    : IIdModel
{
    /// <summary>
    /// Unique identifier for the query history entry (maps to _id in Ditto).
    /// </summary>
    [JsonPropertyName("_id")]
    public required string Id { get; init; }

    /// <summary>
    /// The query string that was executed.
    /// </summary>
    [JsonPropertyName("query")]
    public required string Query { get; init; }

    /// <summary>
    /// The date when the query was created (ISO 8601 format string).
    /// </summary>
    [JsonPropertyName("createdDate")]
    public required string CreatedDate { get; init; }

    /// <summary>
    /// The selected app/database ID (included for compatibility with legacy data).
    /// Typically unused in the current implementation.
    /// </summary>
    [JsonPropertyName("selectedApp_id")]
    public string SelectedAppId { get; init; } = string.Empty;

    /// <summary>
    /// Parameterless constructor for JSON deserialization.
    /// Properties are set via object initializer or JSON deserializer.
    /// </summary>
    public QueryHistory()
    {
    }

    /// <summary>
    /// Creates a new query history entry with the specified values.
    /// SelectedAppId is automatically set to empty string for compatibility.
    /// </summary>
    /// <param name="id">Unique identifier for the query history entry.</param>
    /// <param name="query">The query string that was executed.</param>
    /// <param name="createdDate">The date when the query was created (ISO 8601 format).</param>
    [SetsRequiredMembers]
    public QueryHistory(string id, string query, string createdDate)
        : this()
    {
        Id = id;
        Query = query;
        CreatedDate = createdDate;
        SelectedAppId = string.Empty;
    }
}
