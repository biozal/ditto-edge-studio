using System.Collections.Generic;
using System.ComponentModel;
using System.Text.Json;
using System.Threading.Tasks;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Data.Repositories;
using ModelContextProtocol.Server;

namespace EdgeStudio.Data.McpServer
{
    [McpServerToolType]
    public static class DittoDatabaseTools
    {
        [McpServerTool, Description("Execute a DQL query against the active Ditto database")]
        public static async Task<string> ExecuteDql(
            [Description("The DQL query to execute")] string query,
            [Description("Transport to use: 'local' (default)")] string? transport,
            IQueryService queryService)
        {
            var result = await queryService.ExecuteLocalAsync(query);

            if (result.IsError)
            {
                return JsonSerializer.Serialize(new
                {
                    error = result.ErrorMessage
                });
            }

            if (result.IsMutation)
            {
                return JsonSerializer.Serialize(new
                {
                    isMutation = true,
                    mutatedDocumentIds = result.MutatedDocumentIds,
                    commitId = result.CommitId,
                    executionTimeMs = result.ExecutionTimeMs
                });
            }

            return JsonSerializer.Serialize(new
            {
                resultCount = result.ResultCount,
                executionTimeMs = result.ExecutionTimeMs,
                documents = result.JsonDocuments,
                explainOutput = result.ExplainOutput
            });
        }

        [McpServerTool, Description("List all configured Ditto databases. Returns the active database only (listing all is not yet supported).")]
        public static string ListDatabases(IDittoManager dittoManager)
        {
            var config = dittoManager.SelectedDatabaseConfig;
            if (config == null)
            {
                return JsonSerializer.Serialize(new
                {
                    error = "No database is currently selected.",
                    databases = new object[0]
                });
            }

            return JsonSerializer.Serialize(new
            {
                databases = new[]
                {
                    new
                    {
                        id = config.Id,
                        name = config.Name,
                        databaseId = config.DatabaseId,
                        mode = config.Mode,
                        isBluetoothLeEnabled = config.IsBluetoothLeEnabled,
                        isLanEnabled = config.IsLanEnabled,
                        isAwdlEnabled = config.IsAwdlEnabled,
                        isCloudSyncEnabled = config.IsCloudSyncEnabled
                    }
                },
                note = "Only the active database is returned. Listing all configured databases is not yet supported."
            });
        }

        [McpServerTool, Description("Get the currently active Ditto database configuration")]
        public static string GetActiveDatabase(IDittoManager dittoManager)
        {
            var config = dittoManager.SelectedDatabaseConfig;
            if (config == null)
            {
                return JsonSerializer.Serialize(new
                {
                    error = "No database is currently selected."
                });
            }

            return JsonSerializer.Serialize(new
            {
                id = config.Id,
                name = config.Name,
                databaseId = config.DatabaseId,
                mode = config.Mode,
                authUrl = config.AuthUrl,
                httpApiUrl = config.HttpApiUrl,
                websocketUrl = config.WebsocketUrl,
                isBluetoothLeEnabled = config.IsBluetoothLeEnabled,
                isLanEnabled = config.IsLanEnabled,
                isAwdlEnabled = config.IsAwdlEnabled,
                isCloudSyncEnabled = config.IsCloudSyncEnabled,
                allowUntrustedCerts = config.AllowUntrustedCerts,
                isStrictModeEnabled = config.IsStrictModeEnabled,
                logLevel = config.LogLevel
            });
        }

        [McpServerTool, Description("List all collection names in the active database")]
        public static async Task<string> ListCollections(
            ICollectionsRepository collectionsRepository,
            IDittoManager dittoManager)
        {
            if (dittoManager.SelectedDatabaseConfig == null)
            {
                return JsonSerializer.Serialize(new
                {
                    error = "No database is currently selected."
                });
            }

            var names = await collectionsRepository.GetCollectionNamesAsync();
            return JsonSerializer.Serialize(new
            {
                collections = names,
                count = names.Count
            });
        }
    }
}
