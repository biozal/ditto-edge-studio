using System;
using CommunityToolkit.Mvvm.ComponentModel;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Data.Repositories;
using EdgeStudio.Shared.Services;

namespace EdgeStudio.ViewModels;

/// <summary>
/// Parent ViewModel for subscription details - manages 3 child tab ViewModels
/// </summary>
public partial class SubscriptionDetailsViewModel : DisposableViewModelBase
{
    [ObservableProperty]
    private string _detailsTitle = string.Empty;

    [ObservableProperty]
    private int _selectedTabIndex;

    /// <summary>
    /// Peers List tab ViewModel
    /// </summary>
    public PeersListViewModel PeersList { get; private set; }

    /// <summary>
    /// Presence Viewer tab ViewModel
    /// </summary>
    public PresenceViewerViewModel PresenceViewer { get; private set; }

    /// <summary>
    /// Settings tab ViewModel
    /// </summary>
    public SubscriptionSettingsViewModel Settings { get; private set; }

    /// <summary>
    /// Last updated text from the currently active tab's ViewModel.
    /// </summary>
    public string LastUpdatedText => SelectedTabIndex switch
    {
        0 => PeersList.LastUpdatedText,
        1 => PresenceViewer.LastUpdatedText,
        _ => "--:--:-- --"
    };

    public SubscriptionDetailsViewModel(
        ISyncService syncService,
        IDittoManager dittoManager,
        Lazy<ISystemRepository> systemRepositoryLazy,
        INetworkAdapterService networkAdapterService,
        IToastService? toastService = null)
        : base(toastService)
    {
        // Instantiate child ViewModels (not resolved from DI, following QueryViewModel pattern)
        PeersList = new PeersListViewModel(systemRepositoryLazy, networkAdapterService, toastService);
        PresenceViewer = new PresenceViewerViewModel(systemRepositoryLazy, toastService);
        Settings = new SubscriptionSettingsViewModel(syncService, dittoManager, toastService);

        PeersList.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(PeersListViewModel.LastUpdatedText) && SelectedTabIndex == 0)
                OnPropertyChanged(nameof(LastUpdatedText));
        };

        PresenceViewer.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(PresenceViewerViewModel.LastUpdatedText) && SelectedTabIndex == 1)
                OnPropertyChanged(nameof(LastUpdatedText));
        };
    }

    partial void OnSelectedTabIndexChanged(int value)
    {
        // Tab 0 = Peers List, Tab 1 = Presence Viewer
        switch (value)
        {
            case 0:
                PresenceViewer.StopObserving();
                PeersList.Activate();
                break;
            case 1:
                PeersList.Deactivate();
                PresenceViewer.StartObserving();
                break;
        }

        OnPropertyChanged(nameof(LastUpdatedText));
    }

    /// <summary>
    /// Called when the view becomes active - activate child ViewModels
    /// </summary>
    protected override void OnActivated()
    {
        base.OnActivated();

        if (SelectedTabIndex == 0)
            PeersList.Activate();
        else if (SelectedTabIndex == 1)
            PresenceViewer.StartObserving();
    }

    /// <summary>
    /// Called when the view becomes inactive - deactivate child ViewModels
    /// </summary>
    protected override void OnDeactivated()
    {
        base.OnDeactivated();

        PeersList.Deactivate();
        PresenceViewer.StopObserving();
    }

    protected override void OnDisposing()
    {
        // Dispose child ViewModels if they implement IDisposable
        if (PeersList is IDisposable peersListDisposable)
        {
            peersListDisposable.Dispose();
        }

        base.OnDisposing();
    }
}