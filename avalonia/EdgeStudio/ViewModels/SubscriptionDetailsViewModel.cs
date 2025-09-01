using System;
using System.Collections.ObjectModel;
using System.Linq;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using EdgeStudio.Data;
using EdgeStudio.Models;

namespace EdgeStudio.ViewModels;

public partial class SubscriptionDetailsViewModel : ObservableObject, IDisposable
{
    private readonly Lazy<ISystemService> _systemServiceLazy;
    private bool _isInitialized = false;
    private bool _disposed = false;
    
    [ObservableProperty]
    private string _detailsTitle = "PEERS";
    
    [ObservableProperty]
    private DateTime? _lastUpdated;
    
    [ObservableProperty]
    private bool _isLoading;
    
    [ObservableProperty]
    private string? _errorMessage;
    
    [ObservableProperty]
    private bool _showError;
    
    /// <summary>
    /// Collection of peer sync status information
    /// </summary>
    public ObservableCollection<SyncStatusInfo> Peers { get; }
    
    /// <summary>
    /// Indicates if there are no peers to display
    /// </summary>
    public bool ShowEmptyState => !IsLoading && Peers.Count == 0;
    
    /// <summary>
    /// Indicates if there are peers to display
    /// </summary>
    public bool HasPeers => Peers.Count > 0;
    
    /// <summary>
    /// Formatted last updated time for display
    /// </summary>
    public string LastUpdatedText => LastUpdated?.ToString("h:mm:ss tt") ?? "--:--:-- --";
    
    public SubscriptionDetailsViewModel(Lazy<ISystemService> systemServiceLazy)
    {
        _systemServiceLazy = systemServiceLazy;
        Peers = new ObservableCollection<SyncStatusInfo>();
        
        // Subscribe to collection changes to update LastUpdated and ensure proper sorting
        Peers.CollectionChanged += OnPeersCollectionChanged;
    }
    
    /// <summary>
    /// Initializes the view model and starts observing peers
    /// </summary>
    public void Initialize()
    {
        if (_isInitialized) return;
        
        try
        {
            IsLoading = true;
            HideError();
            
            // Register observer with SystemService (lazy loaded)
            _systemServiceLazy.Value.RegisterLocalObservers(Peers, ShowErrorMessage);
            
            _isInitialized = true;
        }
        catch (Exception ex)
        {
            ShowErrorMessage($"Failed to initialize peers monitoring: {ex.Message}");
        }
        finally
        {
            IsLoading = false;
        }
    }
    
    private void ShowErrorMessage(string message)
    {
        ErrorMessage = message;
        ShowError = true;
    }
    
    private void HideError()
    {
        ShowError = false;
        ErrorMessage = null;
    }
    
    [RelayCommand]
    private void DismissError()
    {
        HideError();
    }
    
    /// <summary>
    /// Ensures peers are properly sorted: Connected first, then by LastUpdateReceivedTime descending
    /// </summary>
    private void EnsureProperSorting()
    {
        if (Peers.Count <= 1) return;
        
        // Create sorted list: Connected peers first (by most recent update), then disconnected peers (by most recent update)
        var sortedPeers = Peers
            .OrderBy(p => p.IsConnected ? 0 : 1)  // Connected first (0), then disconnected (1)
            .ThenByDescending(p => p.Documents.LastUpdateReceivedTime)  // Most recent first within each group
            .ToList();
        
        // Check if current order matches desired order
        bool needsReordering = false;
        for (int i = 0; i < Peers.Count; i++)
        {
            if (Peers[i].Id != sortedPeers[i].Id)
            {
                needsReordering = true;
                break;
            }
        }
        
        // Only reorder if necessary to avoid unnecessary UI updates
        if (needsReordering)
        {
            // Temporarily unsubscribe to avoid infinite recursion
            Peers.CollectionChanged -= OnPeersCollectionChanged;
            
            // Clear and rebuild in correct order
            Peers.Clear();
            foreach (var peer in sortedPeers)
            {
                Peers.Add(peer);
            }
            
            // Resubscribe
            Peers.CollectionChanged += OnPeersCollectionChanged;
        }
    }
    
    private void OnPeersCollectionChanged(object? sender, System.Collections.Specialized.NotifyCollectionChangedEventArgs e)
    {
        LastUpdated = DateTime.Now;
        OnPropertyChanged(nameof(LastUpdatedText));
        OnPropertyChanged(nameof(ShowEmptyState));
        OnPropertyChanged(nameof(HasPeers));
        
        // Ensure proper sorting: Connected peers first, then by LastUpdateReceivedTime desc
        EnsureProperSorting();
    }
    
    public void Dispose()
    {
        Dispose(true);
        GC.SuppressFinalize(this);
    }
    
    protected virtual void Dispose(bool disposing)
    {
        if (!_disposed)
        {
            if (disposing)
            {
                // SystemService handles its own disposal
                // Just clear our collection
                Peers.Clear();
            }
            _disposed = true;
        }
    }
}