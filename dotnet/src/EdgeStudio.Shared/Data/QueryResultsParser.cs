using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace EdgeStudio.Shared.Data
{
    /// <summary>
    /// Parses a list of JSON document strings into a flat table structure
    /// suitable for DataGrid display.
    /// </summary>
    public class QueryResultsParser
    {
        private static readonly JsonSerializerOptions CompactOptions = new() { WriteIndented = false };

        public QueryTableData Parse(IReadOnlyList<string> jsonDocuments)
        {
            if (jsonDocuments.Count == 0)
                return new QueryTableData([], [], false);

            // Parse each document into a JsonObject
            var parsed = new List<JsonObject>();
            foreach (var doc in jsonDocuments)
            {
                try
                {
                    var node = JsonNode.Parse(doc);
                    if (node is JsonObject obj)
                        parsed.Add(obj);
                }
                catch
                {
                    // skip unparseable docs
                }
            }

            if (parsed.Count == 0)
                return new QueryTableData([], [], false);

            // Collect all unique keys — _id always first, rest alphabetical
            var allKeys = new HashSet<string>();
            foreach (var doc in parsed)
                foreach (var kv in doc.AsObject())
                    allKeys.Add(kv.Key);

            var columns = allKeys
                .OrderBy(k => k == "_id" ? string.Empty : k, StringComparer.OrdinalIgnoreCase)
                .ToList();

            // Build rows
            var rows = new List<IReadOnlyList<string>>();
            foreach (var doc in parsed)
            {
                var row = columns.Select(col =>
                {
                    if (!doc.AsObject().TryGetPropertyValue(col, out var node) || node == null)
                        return string.Empty;
                    return node switch
                    {
                        JsonValue v => v.ToString(),
                        JsonObject o => o.ToJsonString(CompactOptions),
                        JsonArray a => a.ToJsonString(CompactOptions),
                        _ => string.Empty
                    };
                }).ToList();
                rows.Add(row);
            }

            return new QueryTableData(columns, rows, false);
        }
    }

    /// <summary>
    /// Structured table data extracted from JSON query results.
    /// </summary>
    public sealed record QueryTableData(
        IReadOnlyList<string> Columns,
        IReadOnlyList<IReadOnlyList<string>> Rows,
        bool IsMutationResult);
}
