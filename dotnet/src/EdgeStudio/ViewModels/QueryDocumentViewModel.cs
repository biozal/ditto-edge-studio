using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Media.Imaging;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Messages;
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

namespace EdgeStudio.ViewModels
{
    /// <summary>
    /// ViewModel for a single query editor tab.
    /// </summary>
    public partial class QueryDocumentViewModel : ObservableObject
    {
        public string Id { get; private set; } = string.Empty;

        [ObservableProperty]
        private string _title = string.Empty;

        private string _queryText = string.Empty;
        private bool _isDirty = false;
        private string _originalQueryText = string.Empty;
        private readonly JsonResultsViewModel? _jsonResults;
        private readonly TableResultsViewModel? _tableResults;
        private readonly ExplainResultsViewModel? _explainResults;
        private readonly IQueryService? _queryService;
        private readonly IQueryMetricsService? _queryMetricsService;
        private readonly IAppMetricsService? _appMetricsService;
        private readonly IAttachmentService? _attachmentService;
        private readonly IToastService? _toastService;
        private string? _lastCollection;

        [ObservableProperty]
        private string _selectedQueryMode = "Local";

        [ObservableProperty]
        private bool _isExecuting = false;

        [ObservableProperty]
        private int _resultCount = 0;

        [ObservableProperty]
        [NotifyPropertyChangedFor(nameof(HasAttachments))]
        private string? _selectedDocumentJson;

        // Attachment state — kept on this ViewModel so bindings work in DocumentViewerView
        public ObservableCollection<AttachmentInfo> DetectedAttachments { get; } = new();
        public bool HasAttachments => DetectedAttachments.Count > 0;

        [ObservableProperty]
        private bool _isLoadingAttachment;

        public ObservableCollection<string> AvailableQueryModes { get; } = new() { "Local" };

        public JsonResultsViewModel? JsonResults => _jsonResults;
        public TableResultsViewModel? TableResults => _tableResults;
        public ExplainResultsViewModel? ExplainResults => _explainResults;

        public string QueryText
        {
            get => _queryText;
            set
            {
                if (SetProperty(ref _queryText, value))
                    UpdateDirtyState();
            }
        }

        public bool IsDirty
        {
            get => _isDirty;
            private set
            {
                if (SetProperty(ref _isDirty, value))
                    UpdateTitle();
            }
        }

        private string _baseTitle = "New Query";

        public QueryDocumentViewModel()
        {
            Id = Guid.NewGuid().ToString();
            _baseTitle = "New Query";
            Title = _baseTitle;
        }

        public QueryDocumentViewModel(
            string title,
            JsonResultsViewModel? jsonResults,
            TableResultsViewModel? tableResults,
            ExplainResultsViewModel? explainResults,
            IQueryService? queryService = null,
            string queryText = "",
            IQueryMetricsService? queryMetricsService = null,
            IAppMetricsService? appMetricsService = null,
            IAttachmentService? attachmentService = null,
            IToastService? toastService = null)
        {
            Id = Guid.NewGuid().ToString();
            _baseTitle = title;
            Title = title;
            _queryText = queryText;
            _originalQueryText = queryText;
            _jsonResults = jsonResults;
            _tableResults = tableResults;
            _explainResults = explainResults;
            _queryService = queryService;
            _queryMetricsService = queryMetricsService;
            _appMetricsService = appMetricsService;
            _attachmentService = attachmentService;
            _toastService = toastService;

            if (_jsonResults != null)
            {
                _jsonResults.DocumentSelected += json => SelectedDocumentJson = json;
                _jsonResults.DocumentDoubleClicked += json =>
                {
                    SelectedDocumentJson = json;
                    WeakReferenceMessenger.Default.Send(new DocumentDoubleClickedMessage(json));
                };
                _jsonResults.AddAttachmentRequested += json => OnAddAttachmentRequested(json);
                _jsonResults.DeleteAttachmentRequested += json => OnDeleteAttachmentRequested(json);
            }
            if (_tableResults != null)
            {
                _tableResults.RowSelected += json => SelectedDocumentJson = json;
                _tableResults.RowDoubleClicked += json =>
                {
                    SelectedDocumentJson = json;
                    WeakReferenceMessenger.Default.Send(new DocumentDoubleClickedMessage(json));
                };
                _tableResults.AddAttachmentRequested += json => OnAddAttachmentRequested(json);
                _tableResults.DeleteAttachmentRequested += json => OnDeleteAttachmentRequested(json);
            }
        }

        private void UpdateDirtyState()
        {
            IsDirty = _queryText != _originalQueryText;
            UpdateBaseTitle();
        }

        private void UpdateBaseTitle()
        {
            if (!string.IsNullOrWhiteSpace(_queryText))
            {
                var trimmed = _queryText.Trim().Replace('\n', ' ').Replace('\r', ' ');
                // Collapse multiple spaces
                while (trimmed.Contains("  "))
                    trimmed = trimmed.Replace("  ", " ");
                _baseTitle = trimmed.Length > 30
                    ? trimmed[..30].TrimEnd() + "..."
                    : trimmed;
            }
            UpdateTitle();
        }

        private void UpdateTitle() => Title = IsDirty ? $"{_baseTitle}*" : _baseTitle;

        [RelayCommand]
        private async Task ExecuteQuery()
        {
            if (string.IsNullOrWhiteSpace(QueryText)) return;
            if (_queryService == null) return;

            IsExecuting = true;
            SelectedDocumentJson = null;
            _lastCollection = ParseCollectionName(QueryText);

            var stopwatch = Stopwatch.StartNew();
            try
            {
                var result = await _queryService.ExecuteLocalAsync(QueryText);
                stopwatch.Stop();
                var elapsedMs = stopwatch.Elapsed.TotalMilliseconds;

                if (result.IsError)
                {
                    _jsonResults?.SetError(result.ErrorMessage!);
                    _tableResults?.Clear();
                    ResultCount = 0;
                }
                else if (result.IsMutation)
                {
                    var summary = result.MutatedDocumentIds.Count > 0
                        ? $"[\"{string.Join("\", \"", result.MutatedDocumentIds)}\"]"
                        : "[]";
                    _jsonResults?.SetResults(new[]
                    {
                        $"{{\n  \"mutated\": {summary},\n  \"count\": {result.MutatedDocumentIds.Count}\n}}"
                    });
                    _tableResults?.Clear();
                    ResultCount = result.MutatedDocumentIds.Count;
                }
                else
                {
                    _jsonResults?.SetResults(result.JsonDocuments);
                    _tableResults?.SetResults(result.JsonDocuments);
                    ResultCount = result.ResultCount;
                }

                // Capture metrics
                if (_queryMetricsService != null)
                {
                    var metric = new QueryMetric(
                        Id: Guid.NewGuid().ToString(),
                        DqlQuery: QueryText,
                        ExecutionTimeMs: elapsedMs,
                        ResultCount: result.ResultCount,
                        ExplainOutput: result.ExplainOutput,
                        Timestamp: DateTime.UtcNow
                    );
                    _queryMetricsService.Capture(metric);
                    _appMetricsService?.IncrementQueryCount();
                    _appMetricsService?.RecordQueryLatency(elapsedMs);
                }

                WeakReferenceMessenger.Default.Send(new QueryExecutedMessage(QueryText, result));
            }
            finally
            {
                if (stopwatch.IsRunning) stopwatch.Stop();
                IsExecuting = false;
            }
        }

        [RelayCommand]
        private async Task CopyDocument()
        {
            if (SelectedDocumentJson == null) return;
            try
            {
                if (Application.Current?.ApplicationLifetime is IClassicDesktopStyleApplicationLifetime { MainWindow: { } w })
                {
                    var clipboard = TopLevel.GetTopLevel(w)?.Clipboard;
                    if (clipboard != null)
                        await clipboard.SetTextAsync(SelectedDocumentJson);
                }
            }
            catch { /* Ignore clipboard errors */ }
        }

        [RelayCommand]
        private void SaveQuery()
        {
            _originalQueryText = _queryText;
            IsDirty = false;
        }

        public void SetHttpAvailable(bool available)
        {
            if (available && !AvailableQueryModes.Contains("HTTP"))
                AvailableQueryModes.Add("HTTP");
            else if (!available)
                AvailableQueryModes.Remove("HTTP");
        }

        private static string? ParseCollectionName(string query)
        {
            var match = System.Text.RegularExpressions.Regex.Match(
                query, @"\bFROM\s+(\w+)", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            return match.Success ? match.Groups[1].Value : null;
        }

        private void OnAddAttachmentRequested(string documentJson)
        {
            var collection = _lastCollection ?? "unknown";
            WeakReferenceMessenger.Default.Send(
                new AddAttachmentRequestedMessage(documentJson, collection, SelectedQueryMode));
        }

        private void OnDeleteAttachmentRequested(string documentJson)
        {
            var collection = _lastCollection ?? "unknown";
            WeakReferenceMessenger.Default.Send(
                new DeleteAttachmentRequestedMessage(documentJson, collection, SelectedQueryMode));
        }

        /// <summary>Called automatically when SelectedDocumentJson changes via [NotifyPropertyChangedFor].</summary>
        partial void OnSelectedDocumentJsonChanged(string? value)
        {
            DetectedAttachments.Clear();
            if (!string.IsNullOrEmpty(value))
            {
                foreach (var token in AttachmentInfo.DetectTokens(value))
                    DetectedAttachments.Add(token);
            }
            OnPropertyChanged(nameof(HasAttachments));
        }

        [RelayCommand]
        private async Task OpenAttachment(AttachmentInfo? attachment)
        {
            if (attachment == null || _attachmentService == null) return;

            IsLoadingAttachment = true;
            try
            {
                byte[] data;
                if (string.Equals(SelectedQueryMode, "HTTP", StringComparison.OrdinalIgnoreCase))
                {
                    data = await _attachmentService.FetchViaHttpAsync(attachment.Id);
                }
                else
                {
                    var token = new Dictionary<string, object>
                    {
                        ["id"] = attachment.Id,
                        ["len"] = attachment.Length,
                        ["metadata"] = attachment.Metadata.ToDictionary(kv => kv.Key, kv => (object)kv.Value)
                    };
                    data = await _attachmentService.FetchAsync(token);
                }

                // Save to temp and open with default OS app
                var fileName = attachment.FileName ?? $"attachment_{attachment.Id[..8]}";
                var tempPath = Path.Combine(Path.GetTempPath(), fileName);
                await File.WriteAllBytesAsync(tempPath, data);

                Process.Start(new ProcessStartInfo
                {
                    FileName = tempPath,
                    UseShellExecute = true
                });
            }
            catch (Exception ex)
            {
                _toastService?.ShowError($"Failed to open attachment: {ex.Message}", "Attachment Error");
            }
            finally
            {
                IsLoadingAttachment = false;
            }
        }

        public bool CanClose() => true;
    }
}
