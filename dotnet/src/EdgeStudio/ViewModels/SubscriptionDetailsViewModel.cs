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
        PresenceViewer = new PresenceViewerViewModel(toastService);
        Settings = new SubscriptionSettingsViewModel(syncService, dittoManager, toastService);
    }

    /// <summary>
    /// Called when the view becomes active - activate child ViewModels
    /// </summary>
    protected override void OnActivated()
    {
        base.OnActivated();

        // Activate the PeersList ViewModel to start observing peers
        PeersList.Activate();
    }

    /// <summary>
    /// Called when the view becomes inactive - deactivate child ViewModels
    /// </summary>
    protected override void OnDeactivated()
    {
        base.OnDeactivated();

        // Deactivate the PeersList ViewModel to stop observing peers
        PeersList.Deactivate();
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