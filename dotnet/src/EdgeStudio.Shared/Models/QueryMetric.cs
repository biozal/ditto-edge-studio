using System;

namespace EdgeStudio.Shared.Models
{
    /// <summary>
    /// Tracks performance data for a single query execution.
    /// </summary>
    public sealed record QueryMetric(
        string Id,
        string DqlQuery,
        double ExecutionTimeMs,
        int ResultCount,
        string ExplainOutput,
        DateTime Timestamp)
    {
        public bool UsedIndex =>
            !string.IsNullOrEmpty(ExplainOutput) &&
            ExplainOutput.Contains("index", StringComparison.OrdinalIgnoreCase);

        public string FormattedExecutionTime => ExecutionTimeMs < 1
            ? "<1 ms"
            : ExecutionTimeMs < 1000
                ? $"{ExecutionTimeMs:F0} ms"
                : $"{ExecutionTimeMs / 1000:F2} s";
    }
}
