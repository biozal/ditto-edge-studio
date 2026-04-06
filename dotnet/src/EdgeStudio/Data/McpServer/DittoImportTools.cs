using System;
using System.ComponentModel;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;
using EdgeStudio.Shared.Data;
using ModelContextProtocol.Server;

namespace EdgeStudio.Data.McpServer
{
    [McpServerToolType]
    public static class DittoImportTools
    {
        [McpServerTool, Description("Import JSON documents from a file into a Ditto collection")]
        public static async Task<string> InsertDocumentsFromFile(
            [Description("Absolute path to the JSON file to import. Must contain a JSON array of objects, each with an '_id' field.")] string filePath,
            [Description("The target collection name to import documents into")] string collection,
            [Description("Import mode: 'insert' (default) uses WITH INITIAL DOCUMENTS — skips existing; 'upsert' uses ON ID CONFLICT DO UPDATE — overwrites existing.")] string? mode,
            IImportService importService,
            IDittoManager dittoManager)
        {
            if (dittoManager.SelectedDatabaseConfig == null)
            {
                return JsonSerializer.Serialize(new
                {
                    success = false,
                    error = "No database is currently selected."
                });
            }

            if (!File.Exists(filePath))
            {
                return JsonSerializer.Serialize(new
                {
                    success = false,
                    error = $"File not found: {filePath}"
                });
            }

            string jsonContent;
            try
            {
                jsonContent = await File.ReadAllTextAsync(filePath);
            }
            catch (Exception ex)
            {
                return JsonSerializer.Serialize(new
                {
                    success = false,
                    error = $"Failed to read file: {ex.Message}"
                });
            }

            int documentCount;
            try
            {
                documentCount = importService.ValidateJson(jsonContent);
            }
            catch (Exception ex)
            {
                return JsonSerializer.Serialize(new
                {
                    success = false,
                    error = $"JSON validation failed: {ex.Message}"
                });
            }

            var useInitialInsert = !string.Equals(mode, "upsert", StringComparison.OrdinalIgnoreCase);

            ImportResult? importResult = null;
            try
            {
                importResult = await importService.ImportAsync(
                    jsonContent,
                    collection,
                    useInitialInsert,
                    progressCallback: null);
            }
            catch (Exception ex)
            {
                return JsonSerializer.Serialize(new
                {
                    success = false,
                    error = $"Import failed: {ex.Message}"
                });
            }

            return JsonSerializer.Serialize(new
            {
                success = importResult.FailureCount == 0,
                filePath,
                collection,
                mode = useInitialInsert ? "insert" : "upsert",
                documentsValidated = documentCount,
                successCount = importResult.SuccessCount,
                failureCount = importResult.FailureCount,
                errors = importResult.Errors
            });
        }
    }
}
