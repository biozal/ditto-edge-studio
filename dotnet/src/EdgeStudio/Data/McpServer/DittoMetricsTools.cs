using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Text.Json;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Services;
using ModelContextProtocol.Server;

namespace EdgeStudio.Data.McpServer
{
    [McpServerToolType]
    public static class DittoMetricsTools
    {
        [McpServerTool, Description("Get query performance metrics captured during this session")]
        public static string GetQueryMetrics(
            [Description("Maximum number of metrics to return (most recent first). Defaults to 50.")] int? count,
            IQueryMetricsService queryMetricsService)
        {
            var all = queryMetricsService.GetAll();
            var limit = count ?? 50;
            var metrics = all
                .Reverse()
                .Take(limit)
                .Select(m => new
                {
                    id = m.Id,
                    query = m.DqlQuery,
                    executionTimeMs = m.ExecutionTimeMs,
                    formattedTime = m.FormattedExecutionTime,
                    resultCount = m.ResultCount,
                    usedIndex = m.UsedIndex,
                    timestamp = m.Timestamp.ToString("o"),
                    explainOutput = m.ExplainOutput
                })
                .ToList();

            return JsonSerializer.Serialize(new
            {
                totalCaptured = all.Count,
                returned = metrics.Count,
                metrics
            });
        }

        [McpServerTool, Description("Get application log entries from Edge Studio's log files")]
        public static string GetAppLogs(
            [Description("Maximum number of log lines to return (from end of log). Defaults to 100.")] int? lines,
            [Description("Optional filter string — only lines containing this text (case-insensitive) are returned.")] string? filter,
            ILoggingService loggingService)
        {
            var combined = loggingService.GetCombinedLogs();
            var allLines = combined.Split('\n', StringSplitOptions.RemoveEmptyEntries);

            IEnumerable<string> filtered = allLines;
            if (!string.IsNullOrWhiteSpace(filter))
            {
                filtered = filtered.Where(l => l.Contains(filter, StringComparison.OrdinalIgnoreCase));
            }

            var limit = lines ?? 100;
            var result = filtered.TakeLast(limit).ToList();

            return JsonSerializer.Serialize(new
            {
                totalLines = allLines.Length,
                returnedLines = result.Count,
                filter,
                logFiles = loggingService.GetLogFilePaths(),
                logs = result
            });
        }

        [McpServerTool, Description("Get Ditto SDK log entries from the Ditto persistence directory log files")]
        public static string GetDittoLogs(
            [Description("Maximum number of log lines to return (from end of log). Defaults to 100.")] int? lines,
            [Description("Optional filter string — only lines containing this text (case-insensitive) are returned.")] string? filter,
            IDittoManager dittoManager,
            ILoggingService loggingService)
        {
            var persistenceDir = dittoManager.GetPersistenceDirectory();
            if (string.IsNullOrEmpty(persistenceDir))
            {
                return JsonSerializer.Serialize(new
                {
                    error = "No persistence directory is configured. Ensure a database is selected.",
                    logs = Array.Empty<string>()
                });
            }

            if (!Directory.Exists(persistenceDir))
            {
                return JsonSerializer.Serialize(new
                {
                    error = $"Persistence directory does not exist: {persistenceDir}",
                    logs = Array.Empty<string>()
                });
            }

            var logFiles = Directory.GetFiles(persistenceDir, "*.log", SearchOption.AllDirectories);
            if (logFiles.Length == 0)
            {
                return JsonSerializer.Serialize(new
                {
                    persistenceDir,
                    message = "No .log files found in the Ditto persistence directory.",
                    logs = Array.Empty<string>()
                });
            }

            var allLines = new List<string>();
            foreach (var logFile in logFiles.OrderBy(f => f))
            {
                try
                {
                    var fileLines = File.ReadAllLines(logFile);
                    allLines.AddRange(fileLines);
                }
                catch (Exception ex)
                {
                    loggingService.Warning($"Could not read Ditto log file {logFile}: {ex.Message}");
                }
            }

            IEnumerable<string> filtered = allLines;
            if (!string.IsNullOrWhiteSpace(filter))
            {
                filtered = filtered.Where(l => l.Contains(filter, StringComparison.OrdinalIgnoreCase));
            }

            var limit = lines ?? 100;
            var result = filtered.TakeLast(limit).ToList();

            return JsonSerializer.Serialize(new
            {
                persistenceDir,
                logFilesFound = logFiles.Length,
                logFiles,
                totalLines = allLines.Count,
                returnedLines = result.Count,
                filter,
                logs = result
            });
        }
    }
}
