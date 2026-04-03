// EdgeStudio/ViewModels/PresenceViewerViewModel.cs
using System;
using System.Collections.Generic;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using EdgeStudio.Shared.Data.Repositories;
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;

namespace EdgeStudio.ViewModels;

/// <summary>
/// ViewModel for the Presence Viewer tab — manages graph state, zoom, and filtering.
/// </summary>
public partial class PresenceViewerViewModel : ViewModelBase
{
    private readonly Lazy<ISystemRepository> _systemRepositoryLazy;
    private PresenceGraphSnapshot? _fullSnapshot;

    [ObservableProperty]
    private PresenceGraphSnapshot? _snapshot;

    [ObservableProperty]
    private Dictionary<string, NodePosition>? _positions;

    [ObservableProperty]
    private float _zoomLevel = 1.4f;

    [ObservableProperty]
    private string _lastUpdatedText = "--:--:-- --";

    [ObservableProperty]
    private bool _showDirectOnly;

    public string ZoomPercentage => $"{(int)(ZoomLevel * 100)}%";

    public PresenceViewerViewModel(
        Lazy<ISystemRepository> systemRepositoryLazy,
        IToastService? toastService = null)
        : base(toastService)
    {
        _systemRepositoryLazy = systemRepositoryLazy;
    }

    partial void OnZoomLevelChanged(float value)
    {
        OnPropertyChanged(nameof(ZoomPercentage));
    }

    partial void OnShowDirectOnlyChanged(bool value)
    {
        ApplyFilterAndLayout();
    }

    /// <summary>
    /// Called by the system repository observer when the presence graph changes.
    /// </summary>
    public void HandleGraphUpdate(PresenceGraphSnapshot snapshot)
    {
        _fullSnapshot = snapshot;
        LastUpdatedText = DateTime.Now.ToString("h:mm:ss tt");
        ApplyFilterAndLayout();
    }

    private void ApplyFilterAndLayout()
    {
        if (_fullSnapshot == null) return;

        var active = ShowDirectOnly
            ? _fullSnapshot.FilterToDirectConnections()
            : _fullSnapshot;

        Snapshot = active;
        Positions = NetworkLayoutEngine.ComputeLayout(active);
    }

    [RelayCommand]
    private void ZoomIn()
    {
        ZoomLevel = Math.Min(ZoomLevel + 0.15f, 3.0f);
    }

    [RelayCommand]
    private void ZoomOut()
    {
        ZoomLevel = Math.Max(ZoomLevel - 0.15f, 0.3f);
    }

    [RelayCommand]
    private void ResetZoom()
    {
        ZoomLevel = 1.4f;
    }

    public void StartObserving()
    {
        _systemRepositoryLazy.Value.RegisterPresenceGraphObserver(
            onUpdate: snapshot =>
            {
                Avalonia.Threading.Dispatcher.UIThread.InvokeAsync(() =>
                {
                    HandleGraphUpdate(snapshot);
                });
            },
            onError: error =>
            {
                Avalonia.Threading.Dispatcher.UIThread.InvokeAsync(() =>
                {
                    ShowError(error, "Presence Viewer");
                });
            });
    }

    public void StopObserving()
    {
        _systemRepositoryLazy.Value.CancelPresenceGraphObserver();
    }
}
