using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace EdgeStudio.Shared.Data
{
    public record ImportResult(int SuccessCount, int FailureCount, List<string> Errors);

    public record ImportProgress(int Current, int Total, string? CurrentDocumentId);

    public interface IImportService
    {
        /// <summary>
        /// Validates JSON content and returns the number of documents found.
        /// Throws if JSON is invalid or documents are missing _id fields.
        /// </summary>
        int ValidateJson(string jsonContent);

        /// <summary>
        /// Imports JSON documents into the specified collection.
        /// </summary>
        /// <param name="jsonContent">Raw JSON string (array of objects)</param>
        /// <param name="collectionName">Target collection name</param>
        /// <param name="useInitialInsert">True for WITH INITIAL DOCUMENTS, false for ON ID CONFLICT DO UPDATE</param>
        /// <param name="progressCallback">Called with progress updates</param>
        Task<ImportResult> ImportAsync(
            string jsonContent,
            string collectionName,
            bool useInitialInsert,
            Action<ImportProgress>? progressCallback = null);
    }
}
