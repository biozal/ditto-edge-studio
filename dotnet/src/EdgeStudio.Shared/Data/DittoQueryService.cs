using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text.Json;
using System.Threading.Tasks;
using EdgeStudio.Shared.Models;

namespace EdgeStudio.Shared.Data
{
    /// <summary>
    /// Executes DQL queries against the active Ditto database and returns structured results.
    /// </summary>
    public class DittoQueryService : IQueryService
    {
        private readonly IDittoManager _dittoManager;
        private static readonly JsonSerializerOptions PrettyOptions = new() { WriteIndented = true };

        public DittoQueryService(IDittoManager dittoManager)
        {
            _dittoManager = dittoManager;
        }

        public async Task<QueryExecutionResult> ExecuteLocalAsync(string dql)
        {
            try
            {
                var ditto = _dittoManager.DittoSelectedApp;
                if (ditto == null)
                    return QueryExecutionResult.Error("No database selected. Please open a database first.");

                var sw = Stopwatch.StartNew();
                var result = await ditto.Store.ExecuteAsync(dql);
                sw.Stop();

                var isMutation = IsMutationQuery(dql);
                var executionTimeMs = sw.Elapsed.TotalMilliseconds;

                QueryExecutionResult queryResult;

                if (isMutation)
                {
                    var mutatedIds = new List<string>();
                    foreach (var item in result.Items)
                    {
                        if (item.Value.TryGetValue("_id", out var id) && id != null)
                            mutatedIds.Add(id.ToString()!);
                        item.Dematerialize();
                    }
                    result.Dispose();

                    queryResult = new QueryExecutionResult(
                        JsonDocuments: [],
                        MutatedDocumentIds: mutatedIds,
                        CommitId: null,
                        ExecutionTimeMs: executionTimeMs,
                        ResultCount: mutatedIds.Count,
                        IsMutation: true,
                        ErrorMessage: null,
                        ExplainOutput: string.Empty);
                }
                else
                {
                    var documents = new List<string>();
                    foreach (var item in result.Items)
                    {
                        try
                        {
                            var json = JsonSerializer.Serialize(item.Value, PrettyOptions);
                            documents.Add(json);
                        }
                        catch
                        {
                            documents.Add("{}");
                        }
                        finally
                        {
                            item.Dematerialize();
                        }
                    }
                    result.Dispose();

                    // Run EXPLAIN and await it inline, mirroring the SwiftUI implementation
                    var explainOutput = await RunExplainAsync(dql, ditto);

                    queryResult = new QueryExecutionResult(
                        JsonDocuments: documents,
                        MutatedDocumentIds: [],
                        CommitId: null,
                        ExecutionTimeMs: executionTimeMs,
                        ResultCount: documents.Count,
                        IsMutation: false,
                        ErrorMessage: null,
                        ExplainOutput: explainOutput);
                }

                return queryResult;
            }
            catch (Exception ex)
            {
                return QueryExecutionResult.Error(ex.Message);
            }
        }

        private static async Task<string> RunExplainAsync(string dql, DittoSDK.Ditto ditto)
        {
            var trimmed = dql.TrimStart();
            if (trimmed.StartsWith("EXPLAIN", StringComparison.OrdinalIgnoreCase))
                return string.Empty;
            try
            {
                using var result = await ditto.Store.ExecuteAsync($"EXPLAIN {dql}");
                if (result.Items.Count == 0)
                    return string.Empty;
                var rawJson = result.Items[0].JsonString();
                using var doc = JsonDocument.Parse(rawJson);
                return JsonSerializer.Serialize(doc.RootElement, PrettyOptions);
            }
            catch (Exception ex)
            {
                return $"EXPLAIN failed: {ex.Message}";
            }
        }

        private static bool IsMutationQuery(string dql)
        {
            var trimmed = dql.TrimStart();
            return trimmed.StartsWith("INSERT", StringComparison.OrdinalIgnoreCase)
                || trimmed.StartsWith("UPDATE", StringComparison.OrdinalIgnoreCase)
                || trimmed.StartsWith("DELETE", StringComparison.OrdinalIgnoreCase)
                || trimmed.StartsWith("EVICT", StringComparison.OrdinalIgnoreCase)
                || trimmed.StartsWith("ALTER", StringComparison.OrdinalIgnoreCase);
        }
    }
}
