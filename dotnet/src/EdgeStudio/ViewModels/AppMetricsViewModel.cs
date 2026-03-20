using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;
using System;
using System.Threading;
using System.Threading.Tasks;

namespace EdgeStudio.ViewModels;

public partial class AppMetricsViewModel : LoadableViewModelBase
{
    private readonly IAppMetricsService _metricsService;
    private readonly IDittoManager _dittoManager;
    private CancellationTokenSource? _refreshCts;

    [ObservableProperty]
    private AppMetricsSnapshot? _currentSnapshot;

    [ObservableProperty]
    private string _lastUpdatedText = "Never";

    public AppMetricsViewModel(IAppMetricsService metricsService, IDittoManager dittoManager, IToastService? toastService = null)
        : base(toastService)
    {
        _metricsService = metricsService;
        _dittoManager = dittoManager;
    }

    protected override void OnActivated()
    {
        base.OnActivated();
        _refreshCts?.Cancel();
        _refreshCts = new CancellationTokenSource();
        _ = RunRefreshLoopAsync(_refreshCts.Token);
    }

    protected override void OnDeactivated()
    {
        base.OnDeactivated();
        _refreshCts?.Cancel();
        _refreshCts = null;
    }

    private async Task RunRefreshLoopAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            await RefreshAsync();
            try { await Task.Delay(TimeSpan.FromSeconds(15), ct); }
            catch (OperationCanceledException) { break; }
        }
    }

    [RelayCommand]
    private async Task RefreshAsync()
    {
        try
        {
            var persistenceDir = _dittoManager.GetPersistenceDirectory();
            var snapshot = await _metricsService.GetSnapshotAsync(persistenceDir, _dittoManager.DittoSelectedApp);
            await Avalonia.Threading.Dispatcher.UIThread.InvokeAsync(() =>
            {
                CurrentSnapshot = snapshot;
                LastUpdatedText = FormatRelativeTime(snapshot.CapturedAt);
            });
        }
        catch (Exception ex)
        {
            ShowError($"Failed to refresh metrics: {ex.Message}");
        }
    }

    private static string FormatRelativeTime(DateTimeOffset capturedAt)
    {
        var elapsed = DateTimeOffset.UtcNow - capturedAt;
        if (elapsed.TotalSeconds < 5) return "Just now";
        if (elapsed.TotalSeconds < 60) return $"{(int)elapsed.TotalSeconds}s ago";
        if (elapsed.TotalMinutes < 60) return $"{(int)elapsed.TotalMinutes}m ago";
        return capturedAt.LocalDateTime.ToString("HH:mm");
    }

    protected override void OnDisposing()
    {
        _refreshCts?.Cancel();
        base.OnDisposing();
    }
}
