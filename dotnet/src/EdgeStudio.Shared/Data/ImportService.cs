using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace EdgeStudio.Shared.Data
{
    public partial class ImportService : IImportService
    {
        private readonly IDittoManager _dittoManager;
        private const int BatchSize = 50;

        public ImportService(IDittoManager dittoManager)
        {
            _dittoManager = dittoManager;
        }

        public int ValidateJson(string jsonContent)
        {
            JsonDocument doc;
            try
            {
                doc = JsonDocument.Parse(jsonContent);
            }
            catch (JsonException ex)
            {
                throw new InvalidOperationException($"Invalid JSON: {ex.Message}");
            }

            if (doc.RootElement.ValueKind != JsonValueKind.Array)
                throw new InvalidOperationException("JSON must be an array of objects.");

            var count = 0;
            foreach (var element in doc.RootElement.EnumerateArray())
            {
                if (element.ValueKind != JsonValueKind.Object)
                    throw new InvalidOperationException($"Element at index {count} is not a JSON object.");

                if (!element.TryGetProperty("_id", out _))
                    throw new InvalidOperationException($"Document at index {count} is missing required '_id' field.");

                count++;
            }

            if (count == 0)
                throw new InvalidOperationException("JSON array is empty.");

            doc.Dispose();
            return count;
        }

        public async Task<ImportResult> ImportAsync(
            string jsonContent,
            string collectionName,
            bool useInitialInsert,
            Action<ImportProgress>? progressCallback = null)
        {
            if (!CollectionNameRegex().IsMatch(collectionName))
                throw new InvalidOperationException(
                    "Collection name may only contain letters, numbers, and underscores.");

            var ditto = _dittoManager.DittoSelectedApp
                ?? throw new InvalidOperationException("No database selected.");

            using var doc = JsonDocument.Parse(jsonContent);
            var elements = new List<JsonElement>();
            foreach (var el in doc.RootElement.EnumerateArray())
                elements.Add(el.Clone());

            var total = elements.Count;
            var successCount = 0;
            var failureCount = 0;
            var errors = new List<string>();

            for (int batchStart = 0; batchStart < total; batchStart += BatchSize)
            {
                var batchEnd = Math.Min(batchStart + BatchSize, total);
                var batchCount = batchEnd - batchStart;

                progressCallback?.Invoke(new ImportProgress(batchStart + 1, total, null));

                try
                {
                    var query = BuildBatchInsertQuery(collectionName, batchCount, useInitialInsert);
                    var arguments = new Dictionary<string, object>();
                    for (int i = 0; i < batchCount; i++)
                    {
                        arguments[$"doc{i}"] = elements[batchStart + i].GetRawText();
                    }

                    var result = await ditto.Store.ExecuteAsync(query, arguments);
                    result.Dispose();
                    successCount += batchCount;
                }
                catch
                {
                    // Batch failed — fall back to individual inserts
                    for (int i = batchStart; i < batchEnd; i++)
                    {
                        var element = elements[i];
                        var docId = element.TryGetProperty("_id", out var idProp)
                            ? idProp.ToString() : $"index-{i}";

                        progressCallback?.Invoke(new ImportProgress(i + 1, total, docId));

                        try
                        {
                            var query = BuildSingleInsertQuery(collectionName, useInitialInsert);
                            var arguments = new Dictionary<string, object>
                            {
                                ["jsonDoc"] = element.GetRawText()
                            };
                            var result = await ditto.Store.ExecuteAsync(query, arguments);
                            result.Dispose();
                            successCount++;
                        }
                        catch (Exception ex)
                        {
                            failureCount++;
                            errors.Add($"Document {docId}: {ex.Message}");
                        }
                    }
                }
            }

            progressCallback?.Invoke(new ImportProgress(total, total, null));
            return new ImportResult(successCount, failureCount, errors);
        }

        private static string BuildBatchInsertQuery(string collection, int batchSize, bool useInitial)
        {
            var placeholders = new string[batchSize];
            for (int i = 0; i < batchSize; i++)
                placeholders[i] = $"(deserialize_json(:doc{i}))";

            var docs = string.Join(", ", placeholders);

            return useInitial
                ? $"INSERT INTO {collection} INITIAL DOCUMENTS {docs}"
                : $"INSERT INTO {collection} DOCUMENTS {docs} ON ID CONFLICT DO UPDATE";
        }

        private static string BuildSingleInsertQuery(string collection, bool useInitial)
        {
            return useInitial
                ? $"INSERT INTO {collection} INITIAL DOCUMENTS (deserialize_json(:jsonDoc))"
                : $"INSERT INTO {collection} DOCUMENTS (deserialize_json(:jsonDoc)) ON ID CONFLICT DO UPDATE";
        }

        [GeneratedRegex(@"^[a-zA-Z0-9_]+$")]
        private static partial Regex CollectionNameRegex();
    }
}
