using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using DittoSDK;
using DittoSDK.Store;
using EdgeStudio.Shared.Models;

namespace EdgeStudio.Shared.Data;

public class AttachmentService : IAttachmentService
{
    private readonly IDittoManager _dittoManager;
    private readonly Dictionary<string, IDisposable> _activeFetchers = new();
    private readonly object _fetcherLock = new();

    public AttachmentService(IDittoManager dittoManager)
    {
        _dittoManager = dittoManager;
    }

    public async Task CreateAndLinkAsync(
        string filePath,
        Dictionary<string, string> metadata,
        string collection,
        string documentId,
        string fieldName)
    {
        var ditto = _dittoManager.DittoSelectedApp
            ?? throw new InvalidOperationException("No Ditto database connected.");

        using var attachment = await ditto.Store.NewAttachmentAsync(filePath, metadata);

        var query = $"UPDATE {collection} ({fieldName} ATTACHMENT) SET {fieldName} = :att WHERE _id = :docId";
        var args = new Dictionary<string, object>
        {
            ["att"] = attachment,
            ["docId"] = documentId
        };

        await ditto.Store.ExecuteAsync(query, args);
    }

    public async Task CreateAndLinkViaHttpAsync(
        string filePath,
        Dictionary<string, string> metadata,
        string collection,
        string documentId,
        string fieldName)
    {
        var config = _dittoManager.SelectedDatabaseConfig
            ?? throw new InvalidOperationException("No database config available.");

        var uploadResult = await HttpUploadAsync(filePath, config);

        var attachmentId = uploadResult.GetProperty("id").GetString() ?? "";
        var attachmentLen = uploadResult.GetProperty("len").GetInt64();

        var updateQuery = $"UPDATE {collection} ({fieldName} ATTACHMENT) SET {fieldName} = :att WHERE _id = :docId";
        var requestBody = new
        {
            statement = updateQuery,
            args = new Dictionary<string, object>
            {
                ["att"] = new { id = attachmentId, len = attachmentLen, metadata },
                ["docId"] = documentId
            }
        };

        using var httpClient = new HttpClient();
        var url = $"https://{config.HttpApiUrl}/api/v5/store/execute";
        var request = new HttpRequestMessage(HttpMethod.Post, url);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", config.HttpApiKey);
        request.Content = new StringContent(
            JsonSerializer.Serialize(requestBody),
            Encoding.UTF8,
            "application/json");

        var response = await httpClient.SendAsync(request);
        response.EnsureSuccessStatusCode();
    }

    public Task<string> FetchAsync(Dictionary<string, object> token)
    {
        var ditto = _dittoManager.DittoSelectedApp
            ?? throw new InvalidOperationException("No Ditto database connected.");

        var tcs = new TaskCompletionSource<string>();
        var attachmentId = token.GetValueOrDefault("id")?.ToString() ?? Guid.NewGuid().ToString();

        // The Ditto .NET SDK v5 attachment fetch API uses a callback-based pattern.
        // The fetcher is stored so it stays alive until the fetch completes or is cancelled.
        var fetcher = ditto.Store.FetchAttachment(token, fetchEvent =>
        {
            switch (fetchEvent)
            {
                case DittoAttachmentFetchEvent.Completed completed:
                    RemoveFetcher(attachmentId);
                    tcs.TrySetResult(completed.Attachment.Id);
                    break;
                case DittoAttachmentFetchEvent.Deleted:
                    RemoveFetcher(attachmentId);
                    tcs.TrySetException(new InvalidOperationException("Attachment was deleted."));
                    break;
            }
        });

        lock (_fetcherLock)
        {
            _activeFetchers[attachmentId] = fetcher;
        }

        return tcs.Task;
    }

    public async Task<byte[]> FetchViaHttpAsync(string attachmentId)
    {
        var config = _dittoManager.SelectedDatabaseConfig
            ?? throw new InvalidOperationException("No database config available.");

        using var httpClient = new HttpClient();
        var url = $"https://{config.HttpApiUrl}/api/v4/attachments/{attachmentId}";
        var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", config.HttpApiKey);

        var response = await httpClient.SendAsync(request);
        response.EnsureSuccessStatusCode();

        return await response.Content.ReadAsByteArrayAsync();
    }

    public void CancelAllFetches()
    {
        lock (_fetcherLock)
        {
            foreach (var fetcher in _activeFetchers.Values)
            {
                fetcher.Dispose();
            }
            _activeFetchers.Clear();
        }
    }

    public void Dispose()
    {
        CancelAllFetches();
    }

    private void RemoveFetcher(string id)
    {
        lock (_fetcherLock)
        {
            if (_activeFetchers.Remove(id, out var fetcher))
            {
                fetcher.Dispose();
            }
        }
    }

    private async Task<JsonElement> HttpUploadAsync(string filePath, DittoDatabaseConfig config)
    {
        using var httpClient = new HttpClient();
        var url = $"https://{config.HttpApiUrl}/api/v4/attachments/upload";

        using var content = new MultipartFormDataContent();
        var fileBytes = await File.ReadAllBytesAsync(filePath);
        var fileContent = new ByteArrayContent(fileBytes);
        fileContent.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
        content.Add(fileContent, "file", Path.GetFileName(filePath));

        var request = new HttpRequestMessage(HttpMethod.Post, url);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", config.HttpApiKey);
        request.Content = content;

        var response = await httpClient.SendAsync(request);
        response.EnsureSuccessStatusCode();

        var responseBody = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(responseBody);
        return doc.RootElement.Clone();
    }
}
