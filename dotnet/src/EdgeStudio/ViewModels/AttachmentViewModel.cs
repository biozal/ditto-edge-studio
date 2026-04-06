using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using Avalonia.Media.Imaging;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Models;

namespace EdgeStudio.ViewModels;

/// <summary>
/// ViewModel for detecting and fetching Ditto attachments found in query result documents.
/// Handles image preview caching, non-image file launching, and progress tracking.
/// </summary>
public partial class AttachmentViewModel : DisposableViewModelBase
{
    private readonly IAttachmentService _attachmentService;

    [ObservableProperty]
    private ObservableCollection<AttachmentInfo> _detectedAttachments = new();

    [ObservableProperty]
    private bool _isLoading;

    [ObservableProperty]
    private string _progressMessage = string.Empty;

    [ObservableProperty]
    private double _progressFraction;

    private readonly Dictionary<string, Bitmap> _imageCache = new();
    private readonly HashSet<string> _loadingIds = new();
    private readonly Dictionary<string, string> _errorMessages = new();
    private string _currentQueryMode = "Local";

    public AttachmentViewModel(IAttachmentService attachmentService)
    {
        _attachmentService = attachmentService;
    }

    /// <summary>
    /// Scans a JSON document string for attachment tokens and populates DetectedAttachments.
    /// Clears any previously detected attachments and cached state.
    /// </summary>
    public void DetectAttachments(string? json)
    {
        DetectedAttachments.Clear();
        _loadingIds.Clear();
        _errorMessages.Clear();
        // Note: image cache is intentionally NOT cleared here to allow reuse across scans.
        // It is cleaned up in OnDisposing.

        if (string.IsNullOrWhiteSpace(json))
            return;

        var tokens = AttachmentInfo.DetectTokens(json);
        foreach (var token in tokens)
        {
            DetectedAttachments.Add(token);
        }
    }

    /// <summary>
    /// Sets the current query mode (e.g. "Local" or "HTTP") which determines
    /// whether local SDK fetch or HTTP fetch is used.
    /// </summary>
    public void SetQueryMode(string mode)
    {
        _currentQueryMode = mode;
    }

    /// <summary>
    /// Returns true if the attachment with the given ID is currently being fetched.
    /// </summary>
    public bool IsLoadingAttachment(string id) => _loadingIds.Contains(id);

    /// <summary>
    /// Returns the error message for the given attachment ID, or null if no error.
    /// </summary>
    public string? GetError(string id) => _errorMessages.GetValueOrDefault(id);

    /// <summary>
    /// Returns the cached Bitmap for the given attachment ID, or null if not yet fetched.
    /// </summary>
    public Bitmap? GetCachedImage(string id) => _imageCache.GetValueOrDefault(id);

    /// <summary>
    /// Fetches an attachment from either the local Ditto SDK or the HTTP API,
    /// depending on the current query mode. For images, the result is decoded
    /// into a Bitmap and cached. For non-images, the data is saved to a temp
    /// file and opened with the system's default application.
    /// </summary>
    [RelayCommand]
    private async Task FetchAttachment(AttachmentInfo attachment)
    {
        if (_loadingIds.Contains(attachment.Id))
            return;

        _loadingIds.Add(attachment.Id);
        _errorMessages.Remove(attachment.Id);
        IsLoading = true;
        ProgressMessage = $"Fetching {attachment.FileName ?? attachment.Id}...";
        ProgressFraction = 0.0;

        try
        {
            byte[] data;

            if (string.Equals(_currentQueryMode, "HTTP", StringComparison.OrdinalIgnoreCase))
            {
                data = await _attachmentService.FetchViaHttpAsync(attachment.Id);
            }
            else
            {
                // Local fetch uses Ditto SDK's DittoAttachment.Data() to get binary content
                var token = new Dictionary<string, object>
                {
                    ["id"] = attachment.Id,
                    ["len"] = attachment.Length,
                    ["metadata"] = attachment.Metadata
                };
                data = await _attachmentService.FetchAsync(token);
            }

            ProgressFraction = 0.75;
            ProgressMessage = "Processing...";

            if (attachment.IsImage)
            {
                using var ms = new MemoryStream(data);
                var bitmap = new Bitmap(ms);

                // Dispose any previously cached bitmap for the same ID
                if (_imageCache.TryGetValue(attachment.Id, out var oldBitmap))
                {
                    oldBitmap.Dispose();
                }

                _imageCache[attachment.Id] = bitmap;
            }
            else
            {
                // Save to temp file and open with default system application
                var extension = Path.GetExtension(attachment.FileName ?? ".bin");
                var tempPath = Path.Combine(Path.GetTempPath(), $"edgestudio_{attachment.Id}{extension}");
                await File.WriteAllBytesAsync(tempPath, data);

                Process.Start(new ProcessStartInfo
                {
                    FileName = tempPath,
                    UseShellExecute = true
                });
            }

            ProgressFraction = 1.0;
            ProgressMessage = string.Empty;
        }
        catch (Exception ex)
        {
            _errorMessages[attachment.Id] = ex.Message;
            ProgressMessage = string.Empty;
        }
        finally
        {
            _loadingIds.Remove(attachment.Id);
            IsLoading = _loadingIds.Count > 0;
        }
    }

    /// <summary>
    /// Cleans up resources: cancels active fetches and disposes cached bitmaps.
    /// </summary>
    protected override void OnDisposing()
    {
        _attachmentService.CancelAllFetches();

        foreach (var bitmap in _imageCache.Values)
        {
            bitmap.Dispose();
        }
        _imageCache.Clear();
        _loadingIds.Clear();
        _errorMessages.Clear();

        base.OnDisposing();
    }
}
