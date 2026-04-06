using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace EdgeStudio.Shared.Data;

public interface IAttachmentService : IDisposable
{
    /// <summary>Local SDK soft limit: 10MB</summary>
    static readonly long LocalSizeLimit = 10 * 1024 * 1024;

    /// <summary>HTTP API hard limit: 20MB</summary>
    static readonly long HttpSizeLimit = 20 * 1024 * 1024;

    Task CreateAndLinkAsync(
        string filePath,
        Dictionary<string, string> metadata,
        string collection,
        string documentId,
        string fieldName);

    Task CreateAndLinkViaHttpAsync(
        string filePath,
        Dictionary<string, string> metadata,
        string collection,
        string documentId,
        string fieldName);

    Task<string> FetchAsync(Dictionary<string, object> token);

    Task<byte[]> FetchViaHttpAsync(string attachmentId);

    void CancelAllFetches();
}
