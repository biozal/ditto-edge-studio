using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;
using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;

namespace EdgeStudio.ViewModels;

/// <summary>
/// ViewModel for Query Metrics display in the inspector.
/// </summary>
public partial class QueryMetricsViewModel : LoadableViewModelBase
{
    private readonly IQueryMetricsService? _metricsService;

    [ObservableProperty]
    private QueryMetric? _latestMetric;

    [ObservableProperty]
    private QueryMetric? _selectedRecord;

    public ObservableCollection<QueryMetric> RecentMetrics { get; } = new();

    public bool HasRecords => RecentMetrics.Count > 0;
    public string RecordCountText => $"{RecentMetrics.Count} records";

    public QueryMetricsViewModel(IQueryMetricsService? metricsService = null, IToastService? toastService = null)
        : base(toastService)
    {
        _metricsService = metricsService;
        if (_metricsService != null)
            _metricsService.MetricsUpdated += OnMetricsUpdated;
    }

    private void OnMetricsUpdated(object? sender, EventArgs e)
    {
        Dispatcher.UIThread.InvokeAsync(() =>
        {
            LatestMetric = _metricsService!.Latest;
            RecentMetrics.Clear();
            foreach (var m in _metricsService.GetAll())
                RecentMetrics.Add(m);
            OnPropertyChanged(nameof(HasRecords));
            OnPropertyChanged(nameof(RecordCountText));
        });
    }

    [RelayCommand]
    private void ClearAll()
    {
        _metricsService?.ClearAll();
    }

    [RelayCommand]
    private async Task CopyExplainOutput()
    {
        if (LatestMetric?.ExplainOutput == null) return;
        try
        {
            if (Application.Current?.ApplicationLifetime is IClassicDesktopStyleApplicationLifetime { MainWindow: { } w })
            {
                var clipboard = TopLevel.GetTopLevel(w)?.Clipboard;
                if (clipboard != null)
                    await clipboard.SetTextAsync(LatestMetric.ExplainOutput);
            }
        }
        catch { }
    }

    protected override void OnDisposing()
    {
        if (_metricsService != null)
            _metricsService.MetricsUpdated -= OnMetricsUpdated;
        base.OnDisposing();
    }
}
