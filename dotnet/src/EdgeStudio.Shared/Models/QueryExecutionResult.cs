using System.Collections.Generic;

namespace EdgeStudio.Shared.Models
{
    /// <summary>
    /// Result of executing a DQL query against a Ditto database.
    /// </summary>
    public sealed record QueryExecutionResult(
        IReadOnlyList<string> JsonDocuments,
        IReadOnlyList<string> MutatedDocumentIds,
        string? CommitId,
        double ExecutionTimeMs,
        int ResultCount,
        bool IsMutation,
        string? ErrorMessage)
    {
        public bool IsError => ErrorMessage != null;

        public static QueryExecutionResult Error(string message) =>
            new([], [], null, 0, 0, false, message);
    }
}
