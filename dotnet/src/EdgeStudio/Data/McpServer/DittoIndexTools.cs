using System.ComponentModel;
using System.Text.Json;
using System.Threading.Tasks;
using EdgeStudio.Shared.Data;
using ModelContextProtocol.Server;

namespace EdgeStudio.Data.McpServer
{
    [McpServerToolType]
    public static class DittoIndexTools
    {
        [McpServerTool, Description("Create an index on a collection field to improve query performance")]
        public static async Task<string> CreateIndex(
            [Description("The collection name to create an index on")] string collection,
            [Description("The field name to index")] string field,
            IQueryService queryService)
        {
            var dql = $"CREATE INDEX ON {collection} (SORT ASC {field})";
            var result = await queryService.ExecuteLocalAsync(dql);

            if (result.IsError)
            {
                return JsonSerializer.Serialize(new
                {
                    success = false,
                    error = result.ErrorMessage,
                    dql
                });
            }

            return JsonSerializer.Serialize(new
            {
                success = true,
                message = $"Index created on {collection}.{field}",
                dql,
                executionTimeMs = result.ExecutionTimeMs
            });
        }

        [McpServerTool, Description("Drop an existing index by name")]
        public static async Task<string> DropIndex(
            [Description("The name of the index to drop")] string indexName,
            IQueryService queryService)
        {
            var dql = $"DROP INDEX {indexName}";
            var result = await queryService.ExecuteLocalAsync(dql);

            if (result.IsError)
            {
                return JsonSerializer.Serialize(new
                {
                    success = false,
                    error = result.ErrorMessage,
                    dql
                });
            }

            return JsonSerializer.Serialize(new
            {
                success = true,
                message = $"Index '{indexName}' dropped successfully",
                dql,
                executionTimeMs = result.ExecutionTimeMs
            });
        }

        [McpServerTool, Description("List all indexes in the active database")]
        public static async Task<string> ListIndexes(
            IQueryService queryService,
            IDittoManager dittoManager)
        {
            if (dittoManager.SelectedDatabaseConfig == null)
            {
                return JsonSerializer.Serialize(new
                {
                    error = "No database is currently selected."
                });
            }

            var result = await queryService.ExecuteLocalAsync("SHOW INDEXES");

            if (result.IsError)
            {
                return JsonSerializer.Serialize(new
                {
                    error = result.ErrorMessage
                });
            }

            return JsonSerializer.Serialize(new
            {
                indexes = result.JsonDocuments,
                count = result.ResultCount,
                executionTimeMs = result.ExecutionTimeMs
            });
        }
    }
}
