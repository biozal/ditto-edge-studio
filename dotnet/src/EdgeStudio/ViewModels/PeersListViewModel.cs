using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Avalonia.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Shared.Data.Repositories;
using EdgeStudio.Shared.Messages;
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;

namespace EdgeStudio.ViewModels;

/// <summary>
/// ViewModel for the Peers List tab - manages peer synchronization status display with dual data sources.
/// Uses observable wrappers and throttled sorting to eliminate UI tearing during frequent updates.
/// </summary>
public partial class PeersListViewModel : LoadableViewModelBase
{
    private readonly Lazy<ISystemRepository> _systemRepositoryLazy;
    private readonly INetworkAdapterService _networkAdapterService;
    private bool _isObserverActive = false;
    private Timer? _sortThrottleTimer;
    private Action<string>? _errorCallback; // Store error callback for re-registering observers

    /// <summary>
    /// All peer cards (remote, server, and local)
    /// Local peer is always the last item in the collection
    /// </summary>
    public ObservableCollection<ObservablePeerCardInfo> PeerCards { get; }

    /// <summary>
    /// Local network adapters, populated once on activation.
    /// </summary>
    public ObservableCollection<NetworkAdapterInfo> NetworkAdapters { get; }

    /// <summary>
    /// Indicates if there are no peers to display
    /// </summary>
    public bool ShowEmptyState => !IsLoading && PeerCards.Count == 0;

    /// <summary>
    /// Indicates if there are peers to display (excluding local peer)
    /// </summary>
    public bool HasPeers => PeerCards.Any(p => p.CardType != PeerCardType.Local);

    /// <summary>
    /// True when there is at least one network adapter to display.
    /// </summary>
    public bool HasNetworkAdapters => NetworkAdapters.Count > 0;

    /// <summary>
    /// Last time the peers collection was updated
    /// </summary>
    public DateTime? LastUpdated { get; private set; }

    /// <summary>
    /// Formatted last updated time for display
    /// </summary>
    public string LastUpdatedText => LastUpdated?.ToString("h:mm:ss tt") ?? "--:--:-- --";

    public PeersListViewModel(
        Lazy<ISystemRepository> systemRepositoryLazy,
        INetworkAdapterService networkAdapterService,
        IToastService? toastService = null)
        : base(toastService)
    {
        _systemRepositoryLazy = systemRepositoryLazy;
        _networkAdapterService = networkAdapterService;
        PeerCards = new ObservableCollection<ObservablePeerCardInfo>();
        NetworkAdapters = new ObservableCollection<NetworkAdapterInfo>();

        // Subscribe to collection changes to update LastUpdated and trigger throttled sorting
        PeerCards.CollectionChanged += OnPeersCollectionChanged;
    }

    /// <summary>
    /// Called when the view becomes active - start observing peers
    /// </summary>
    protected override void OnActivated()
    {
        base.OnActivated();

        // Only register observer if not already active
        if (_isObserverActive) return;

        try
        {
            IsLoading = true;

            // Store error callback for re-registering observers when sync restarts
            _errorCallback = msg => ShowError(msg);

            // Register observer with SystemRepository (lazy loaded)
            // Local peer will be added as the last item in PeerCards
            _systemRepositoryLazy.Value.RegisterPeerCardObservers(PeerCards, _errorCallback);

            _isObserverActive = true;

            // Load network adapters in background; update on UI thread when done
            _ = Task.Run(() => _networkAdapterService.GetAdapters()).ContinueWith(t =>
            {
                if (t.IsCompletedSuccessfully)
                {
                    Dispatcher.UIThread.InvokeAsync(() =>
                    {
                        NetworkAdapters.Clear();
                        foreach (var adapter in t.Result)
                            NetworkAdapters.Add(adapter);
                        OnPropertyChanged(nameof(HasNetworkAdapters));
                    });
                }
            });
        }
        catch (Exception ex)
        {
            ShowError($"Failed to initialize peers monitoring: {ex.Message}");
        }
        finally
        {
            IsLoading = false;
        }
    }

    /// <summary>
    /// Called when the view becomes inactive - stop observing peers
    /// </summary>
    protected override void OnDeactivated()
    {
        base.OnDeactivated();

        // Cancel the observer and clear resources
        if (_isObserverActive && _systemRepositoryLazy.IsValueCreated)
        {
            _systemRepositoryLazy.Value.CloseSelectedDatabase();
            _isObserverActive = false;
        }

        // Cleanup throttle timer
        _sortThrottleTimer?.Dispose();
        _sortThrottleTimer = null;

        // Clear collections to free memory
        PeerCards.Clear();
        NetworkAdapters.Clear();
        LastUpdated = null;

        OnPropertyChanged(nameof(LastUpdatedText));
        OnPropertyChanged(nameof(ShowEmptyState));
        OnPropertyChanged(nameof(HasPeers));
    }

    /// <summary>
    /// Requests throttled sort (max once per 500ms)
    /// KEY PERFORMANCE OPTIMIZATION: Prevents constant sorting during rapid updates
    /// </summary>
    private void RequestThrottledSort()
    {
        _sortThrottleTimer?.Dispose();

        _sortThrottleTimer = new Timer(_ =>
        {
            Dispatcher.UIThread.InvokeAsync(() =>
            {
                PerformSort();
            });
        }, null, 500, Timeout.Infinite);
    }

    /// <summary>
    /// Efficient in-place sorting using Move operations
    /// KEY PERFORMANCE OPTIMIZATION: Uses Move instead of Clear/Add to preserve UI elements
    /// Local peer (CardType.Local) is always sorted to the bottom
    /// </summary>
    private void PerformSort()
    {
        if (PeerCards.Count <= 1) return;

        // Create sorted list: Remote/Server peers sorted by connection and time, Local peer always at bottom
        var sortedPeers = PeerCards
            .Select((peer, index) => new { Peer = peer, OriginalIndex = index })
            .OrderBy(x => x.Peer.CardType == PeerCardType.Local ? 1 : 0)  // Local last (1), Remote/Server first (0)
            .ThenBy(x => x.Peer.IsConnected ? 0 : 1)  // Connected first (0), then disconnected (1)
            .ThenByDescending(x => x.Peer.LastUpdated)  // Most recent first within each group
            .ThenBy(x => x.OriginalIndex)  // Stable sort: preserve original order for equal items
            .Select(x => x.Peer)
            .ToList();

        // Check if current order matches desired order
        bool needsReordering = false;
        for (int i = 0; i < PeerCards.Count; i++)
        {
            if (PeerCards[i].Id != sortedPeers[i].Id)
            {
                needsReordering = true;
                break;
            }
        }

        if (!needsReordering) return;

        // Temporarily unsubscribe to avoid infinite recursion
        PeerCards.CollectionChanged -= OnPeersCollectionChanged;

        try
        {
            // Use Move operations to reorder in place
            // This is MUCH faster than Clear + Add because it preserves UI elements
            for (int i = 0; i < sortedPeers.Count; i++)
            {
                var targetPeer = sortedPeers[i];
                var currentIndex = -1;

                // Find current position of target peer
                for (int j = i; j < PeerCards.Count; j++)
                {
                    if (PeerCards[j].Id == targetPeer.Id)
                    {
                        currentIndex = j;
                        break;
                    }
                }

                // Move to correct position if not already there
                if (currentIndex != i && currentIndex >= 0)
                {
                    PeerCards.Move(currentIndex, i);
                }
            }
        }
        finally
        {
            // Resubscribe
            PeerCards.CollectionChanged += OnPeersCollectionChanged;
        }
    }

    private void OnPeersCollectionChanged(object? sender, System.Collections.Specialized.NotifyCollectionChangedEventArgs e)
    {
        LastUpdated = DateTime.Now;
        OnPropertyChanged(nameof(LastUpdatedText));
        OnPropertyChanged(nameof(ShowEmptyState));
        OnPropertyChanged(nameof(HasPeers));

        // Request throttled sort instead of sorting immediately
        RequestThrottledSort();
    }

    protected override void OnDisposing()
    {
        // Unsubscribe from collection changes
        PeerCards.CollectionChanged -= OnPeersCollectionChanged;

        // Cleanup throttle timer
        _sortThrottleTimer?.Dispose();
        _sortThrottleTimer = null;

        // Clear collections
        PeerCards.Clear();
        NetworkAdapters.Clear();

        base.OnDisposing();
    }
}
