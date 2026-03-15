using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Threading.Tasks;
using Avalonia.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using DittoSDK;
using EdgeStudio.Models.Logging;
using EdgeStudio.Services;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Services;

namespace EdgeStudio.ViewModels;

public enum LogSourceTab { DittoSdk, AppLogs, Imported }

/// <summary>
/// Performance design:
/// - A DispatcherTimer polls every 250 ms. The UI thread is never flooded.
/// - When new entries exist, filtering runs on a Task.Run thread to keep the UI responsive.
/// - FilteredEntries is a plain IReadOnlyList property replaced in one assignment (1 binding
///   notification) instead of ObservableCollection.Clear() + 200×Add() (201 notifications).
/// - _isRefreshing prevents overlapping refresh tasks.
/// </summary>
public partial class LoggingViewModel : LoadableViewModelBase
{
    private readonly DittoLogCaptureService _captureService;
    private readonly ILoggingService? _loggingService;
    private readonly DispatcherTimer _pollTimer;
    private bool _isRefreshing;
    private volatile List<LogEntry> _appLogEntries = new();
    private bool _appLogsLoaded;

    // ── Search / Component ──────────────────────────────────────────────────

    [ObservableProperty]
    private string _searchText = string.Empty;

    [ObservableProperty]
    private string _selectedSdkLogLevel = string.Empty;

    [ObservableProperty]
    private string _selectedComponent = "All";

    [ObservableProperty]
    private int _totalEntryCount;

    [ObservableProperty]
    private IReadOnlyList<LogEntry> _filteredEntries = Array.Empty<LogEntry>();

    // ── Source tabs ─────────────────────────────────────────────────────────

    [ObservableProperty]
    private LogSourceTab _selectedSource = LogSourceTab.DittoSdk;

    public bool IsSourceDittoSdk => SelectedSource == LogSourceTab.DittoSdk;
    public bool IsSourceAppLogs  => SelectedSource == LogSourceTab.AppLogs;
    public bool IsSourceImported => SelectedSource == LogSourceTab.Imported;

    [ObservableProperty]
    private int _appLogsEntryCount;

    // ── Level chips ─────────────────────────────────────────────────────────

    [ObservableProperty]
    private bool _isErrorSelected = true;

    [ObservableProperty]
    private bool _isWarningSelected = true;

    [ObservableProperty]
    private bool _isInfoSelected = true;

    [ObservableProperty]
    private bool _isDebugSelected = true;

    [ObservableProperty]
    private bool _isVerboseSelected = true;

    // ── Date filter ─────────────────────────────────────────────────────────

    [ObservableProperty]
    private bool _isDateFilterEnabled;

    [ObservableProperty]
    private DateTime? _dateFilterStart = DateTime.Today;

    [ObservableProperty]
    private DateTime? _dateFilterEnd = DateTime.Now;

    // ── Component filter visibility ─────────────────────────────────────────

    [ObservableProperty]
    private bool _isComponentFilterVisible = true;

    // ── Derived display state ────────────────────────────────────────────────

    public bool IsEmpty       => !IsLoading && FilteredEntries.Count == 0;
    public bool HasEntries    => !IsLoading && FilteredEntries.Count > 0;
    public bool HasSearchText => !string.IsNullOrEmpty(SearchText);

    // ── Footer ──────────────────────────────────────────────────────────────

    public string FooterText
    {
        get
        {
            var displayed = FilteredEntries.Count;
            var total     = TotalEntryCount;
            var isFiltered = IsDateFilterEnabled
                || !string.IsNullOrWhiteSpace(SearchText)
                || SelectedComponent != "All"
                || !IsErrorSelected || !IsWarningSelected
                || !IsInfoSelected  || !IsDebugSelected || !IsVerboseSelected;

            if (isFiltered)
                return $"{displayed} entries";
            if (displayed < total)
                return $"Showing {displayed} of {total} (most recent)";
            return $"{displayed} entries";
        }
    }

    // ── Options ─────────────────────────────────────────────────────────────

    public IReadOnlyList<string> LogLevelOptions { get; } =
        new[] { "verbose", "debug", "info", "warning", "error" };

    public IReadOnlyList<string> ComponentOptions { get; } =
        new[] { "All", "Sync", "Store", "Query", "Observer", "Transport", "Auth", "Other" };

    // ── Constructor ─────────────────────────────────────────────────────────

    public LoggingViewModel(
        DittoLogCaptureService captureService,
        IDittoManager dittoManager,
        ILoggingService? loggingService = null,
        IToastService? toastService = null)
        : base(toastService)
    {
        _captureService = captureService;
        _loggingService = loggingService;
        _captureService.Cleared += OnCaptureServiceCleared;

        // Initialize the dropdown to match the level set by DittoManager from the database config.
        // Set the backing field directly to avoid triggering OnSelectedSdkLogLevelChanged,
        // which would call DittoLogger.MinimumLogLevel again unnecessarily.
        _selectedSdkLogLevel = dittoManager.SelectedDatabaseConfig?.LogLevel ?? "info";

        _pollTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
        _pollTimer.Tick += OnPollTimerTick;
    }

    // ── Lifecycle ────────────────────────────────────────────────────────────

    protected override void OnActivated()
    {
        base.OnActivated();
        _captureService.StartCapture();
        _pollTimer.Start();
        _ = RefreshEntriesAsync();
    }

    protected override void OnDeactivated()
    {
        base.OnDeactivated();
        _pollTimer.Stop();
    }

    // ── Property-change hooks ────────────────────────────────────────────────

    partial void OnSearchTextChanged(string value)
    {
        OnPropertyChanged(nameof(HasSearchText));
        OnPropertyChanged(nameof(FooterText));
        _ = RefreshEntriesAsync();
    }

    partial void OnSelectedComponentChanged(string value)
    {
        OnPropertyChanged(nameof(FooterText));
        _ = RefreshEntriesAsync();
    }

    partial void OnSelectedSdkLogLevelChanged(string value)
    {
        try
        {
            DittoLogger.MinimumLogLevel = DittoLogLevelHelper.Parse(value);
        }
        catch { /* ignore if Ditto not yet initialized */ }
    }

    partial void OnSelectedSourceChanged(LogSourceTab value)
    {
        OnPropertyChanged(nameof(IsSourceDittoSdk));
        OnPropertyChanged(nameof(IsSourceAppLogs));
        OnPropertyChanged(nameof(IsSourceImported));
        IsComponentFilterVisible = value != LogSourceTab.AppLogs;

        if (value == LogSourceTab.AppLogs && !_appLogsLoaded)
            _ = LoadAppLogsAsync();
        else
            _ = RefreshEntriesAsync();
    }

    partial void OnIsErrorSelectedChanged(bool value)   { OnPropertyChanged(nameof(FooterText)); _ = RefreshEntriesAsync(); }
    partial void OnIsWarningSelectedChanged(bool value)  { OnPropertyChanged(nameof(FooterText)); _ = RefreshEntriesAsync(); }
    partial void OnIsInfoSelectedChanged(bool value)     { OnPropertyChanged(nameof(FooterText)); _ = RefreshEntriesAsync(); }
    partial void OnIsDebugSelectedChanged(bool value)    { OnPropertyChanged(nameof(FooterText)); _ = RefreshEntriesAsync(); }
    partial void OnIsVerboseSelectedChanged(bool value)  { OnPropertyChanged(nameof(FooterText)); _ = RefreshEntriesAsync(); }

    partial void OnIsDateFilterEnabledChanged(bool value)
    {
        OnPropertyChanged(nameof(FooterText));
        _ = RefreshEntriesAsync();
    }

    partial void OnDateFilterStartChanged(DateTime? value) => _ = RefreshEntriesAsync();
    partial void OnDateFilterEndChanged(DateTime? value)   => _ = RefreshEntriesAsync();

    partial void OnFilteredEntriesChanged(IReadOnlyList<LogEntry> value)
    {
        OnPropertyChanged(nameof(FooterText));
        OnPropertyChanged(nameof(IsEmpty));
        OnPropertyChanged(nameof(HasEntries));
    }

    partial void OnTotalEntryCountChanged(int value) => OnPropertyChanged(nameof(FooterText));

    // ── Commands ─────────────────────────────────────────────────────────────

    [RelayCommand]
    private Task RefreshAsync()
    {
        if (SelectedSource == LogSourceTab.AppLogs)
        {
            _appLogsLoaded = false;
            return LoadAppLogsAsync();
        }
        return RefreshEntriesAsync();
    }

    [RelayCommand]
    private void ClearCurrentSource()
    {
        switch (SelectedSource)
        {
            case LogSourceTab.DittoSdk:
                _captureService.Clear();
                break;

            case LogSourceTab.AppLogs:
                _loggingService?.ClearAllLogs();
                _appLogEntries = new List<LogEntry>();
                _appLogsLoaded = false;
                AppLogsEntryCount = 0;
                Dispatcher.UIThread.Post(() =>
                {
                    FilteredEntries = Array.Empty<LogEntry>();
                    TotalEntryCount = 0;
                });
                break;

            case LogSourceTab.Imported:
                // Not yet implemented
                break;
        }
    }

    [RelayCommand]
    private void SelectSourceDittoSdk() => SelectedSource = LogSourceTab.DittoSdk;

    [RelayCommand]
    private void SelectSourceAppLogs() => SelectedSource = LogSourceTab.AppLogs;

    [RelayCommand]
    private void SelectSourceImported() => SelectedSource = LogSourceTab.Imported;

    [RelayCommand]
    private void ClearSearch() => SearchText = string.Empty;

    [RelayCommand]
    private void ClearDateFilter()
    {
        IsDateFilterEnabled = false;
        DateFilterStart = DateTime.Today;
        DateFilterEnd   = DateTime.Now;
    }

    // ── Timer + event handlers ────────────────────────────────────────────────

    private async void OnPollTimerTick(object? sender, EventArgs e)
    {
        if (SelectedSource != LogSourceTab.DittoSdk) return;
        if (!_captureService.HasNewEntries) return;
        await RefreshEntriesAsync();
    }

    private void OnCaptureServiceCleared(object? sender, EventArgs e)
    {
        Dispatcher.UIThread.Post(() =>
        {
            FilteredEntries = Array.Empty<LogEntry>();
            TotalEntryCount = 0;
        });
    }

    // ── App logs loading ──────────────────────────────────────────────────────

    private async Task LoadAppLogsAsync()
    {
        if (_loggingService == null)
        {
            _ = RefreshEntriesAsync();
            return;
        }

        await Task.Run(() =>
        {
            var raw = _loggingService.GetCombinedLogs();
            var parsed = ParseSerilogEntries(raw);
            _appLogEntries = parsed;
            _appLogsLoaded = true;
        });

        AppLogsEntryCount = _appLogEntries.Count;
        _ = RefreshEntriesAsync();
    }

    private static List<LogEntry> ParseSerilogEntries(string raw)
    {
        var entries = new List<LogEntry>();
        if (string.IsNullOrWhiteSpace(raw)) return entries;

        foreach (var line in raw.Split('\n', StringSplitOptions.RemoveEmptyEntries))
        {
            var entry = TryParseSerilogLine(line.Trim());
            if (entry != null) entries.Add(entry);
        }
        return entries;
    }

    private static LogEntry? TryParseSerilogLine(string line)
    {
        // Format: "yyyy-MM-dd HH:mm:ss.fff [LVL] Message…"
        if (line.Length < 27) return null;

        if (!DateTimeOffset.TryParseExact(
                line[..23],
                "yyyy-MM-dd HH:mm:ss.fff",
                CultureInfo.InvariantCulture,
                DateTimeStyles.None,
                out var ts))
            return null;

        var lb = line.IndexOf('[', 23);
        var rb = line.IndexOf(']', lb + 1);
        if (lb < 0 || rb < 0) return null;

        var levelStr = line[(lb + 1)..rb];
        var level = levelStr switch
        {
            "ERR" => AppLogLevel.Error,
            "WRN" => AppLogLevel.Warning,
            "INF" => AppLogLevel.Info,
            "DBG" => AppLogLevel.Debug,
            "VRB" => AppLogLevel.Verbose,
            _     => AppLogLevel.Info
        };

        var message = rb + 2 < line.Length ? line[(rb + 2)..].Trim() : string.Empty;
        return new LogEntry(
            Id:        Guid.NewGuid(),
            Timestamp: ts,
            Level:     level,
            Message:   message,
            Component: LogEntry.DetectComponent(message),
            Source:    LogEntrySource.Application,
            RawLine:   line
        );
    }

    // ── Core refresh ──────────────────────────────────────────────────────────

    private async Task RefreshEntriesAsync()
    {
        if (_isRefreshing) return;
        _isRefreshing = true;

        try
        {
            // Capture all filter state on the UI thread before going async.
            var source      = SelectedSource;
            var searchText  = SearchText;
            var component   = SelectedComponent;
            var isError     = IsErrorSelected;
            var isWarn      = IsWarningSelected;
            var isInfo      = IsInfoSelected;
            var isDebug     = IsDebugSelected;
            var isVerbose   = IsVerboseSelected;
            var isDateFilter = IsDateFilterEnabled;
            var dateStart   = DateFilterStart;
            var dateEnd     = DateFilterEnd;

            // Snapshot the source entries on the UI thread.
            List<LogEntry> sourceEntries = source switch
            {
                LogSourceTab.DittoSdk => _captureService.GetSnapshot(),
                LogSourceTab.AppLogs  => _appLogEntries,
                _                     => new List<LogEntry>()
            };

            var (result, totalCount) = await Task.Run(() =>
                BuildFilteredSnapshot(
                    sourceEntries, searchText, source, component,
                    isError, isWarn, isInfo, isDebug, isVerbose,
                    isDateFilter, dateStart, dateEnd));

            FilteredEntries = result;
            TotalEntryCount = totalCount;
            OnPropertyChanged(nameof(FooterText));
        }
        finally
        {
            _isRefreshing = false;
        }
    }

    private static (List<LogEntry> filtered, int total) BuildFilteredSnapshot(
        List<LogEntry> sourceEntries,
        string searchText,
        LogSourceTab source,
        string selectedComponent,
        bool isError, bool isWarn, bool isInfo, bool isDebug, bool isVerbose,
        bool isDateFilter, DateTime? dateStart, DateTime? dateEnd)
    {
        var total = sourceEntries.Count;
        IEnumerable<LogEntry> entries = sourceEntries;

        // Level filter
        entries = entries.Where(e =>
            (e.Level == AppLogLevel.Error   && isError)  ||
            (e.Level == AppLogLevel.Warning && isWarn)   ||
            (e.Level == AppLogLevel.Info    && isInfo)   ||
            (e.Level == AppLogLevel.Debug   && isDebug)  ||
            (e.Level == AppLogLevel.Verbose && isVerbose));

        // Date filter
        if (isDateFilter && dateStart.HasValue && dateEnd.HasValue)
        {
            var start = dateStart.Value;
            var end   = dateEnd.Value.Date.AddDays(1);
            entries = entries.Where(e =>
                e.Timestamp.DateTime >= start && e.Timestamp.DateTime < end);
        }

        // Component filter (DittoSdk and Imported only)
        if (source != LogSourceTab.AppLogs
            && selectedComponent != "All"
            && Enum.TryParse<LogComponent>(selectedComponent, out var comp))
        {
            entries = entries.Where(comp);
        }

        // Text search
        if (!string.IsNullOrWhiteSpace(searchText))
            entries = entries.Where(searchText);

        var result = new List<LogEntry>(200);
        entries.TakeLast(200, result);
        return (result, total);
    }

    protected override void OnDisposing()
    {
        _pollTimer.Stop();
        _captureService.Cleared -= OnCaptureServiceCleared;
        base.OnDisposing();
    }
}

// ---------------------------------------------------------------------------
// Local extension methods — allocation-efficient filtering
// ---------------------------------------------------------------------------

file static class FilterExtensions
{
    internal static IEnumerable<LogEntry> Where(this IEnumerable<LogEntry> source, LogComponent component)
    {
        foreach (var e in source)
            if (e.Component == component) yield return e;
    }

    internal static IEnumerable<LogEntry> Where(this IEnumerable<LogEntry> source, string searchText)
    {
        foreach (var e in source)
            if (e.Message.Contains(searchText, StringComparison.OrdinalIgnoreCase)) yield return e;
    }

    internal static void TakeLast(this IEnumerable<LogEntry> source, int count, List<LogEntry> result)
    {
        var buffer = new LogEntry[count];
        var index  = 0;
        var total  = 0;

        foreach (var entry in source)
        {
            buffer[index % count] = entry;
            index++;
            total++;
        }

        if (total == 0) return;

        var take  = Math.Min(total, count);
        var start = total > count ? index % count : 0;

        for (var i = 0; i < take; i++)
            result.Add(buffer[(start + i) % count]);
    }
}
