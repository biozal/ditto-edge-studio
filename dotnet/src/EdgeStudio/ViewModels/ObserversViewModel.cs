using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using Avalonia.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CommunityToolkit.Mvvm.Messaging;
using DittoSDK.Store;
using EdgeStudio.Shared.Data.Repositories;
using EdgeStudio.Shared.Messages;
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;

namespace EdgeStudio.ViewModels;

public partial class ObserversViewModel : LoadableViewModelBase
{
    private readonly IObserverRepository _observerRepository;

    [ObservableProperty]
    private string _listingTitle = "OBSERVERS";

    [ObservableProperty]
    private string _detailsTitle = "OBSERVER EVENTS";

    [ObservableProperty]
    private DittoDatabaseObserver? _selectedObserver;

    [ObservableProperty]
    private ObserverEvent? _selectedEvent;

    [ObservableProperty]
    private string _eventFilterMode = "items"; // "items", "inserted", "updated"

    [ObservableProperty]
    private string _detailViewMode = "raw"; // "raw" or "table"

    // Boolean helpers for XAML binding
    public bool IsRawMode => DetailViewMode == "raw";
    public bool IsTableMode => DetailViewMode == "table";
    public bool IsFilterItems => EventFilterMode == "items";
    public bool IsFilterInserted => EventFilterMode == "inserted";
    public bool IsFilterUpdated => EventFilterMode == "updated";

    /// <summary>
    /// All observer definitions for the current database.
    /// </summary>
    public ObservableCollection<DittoDatabaseObserver> Items { get; } = new();

    /// <summary>
    /// Events for the currently selected observer (session-only, not persisted).
    /// </summary>
    public ObservableCollection<ObserverEvent> Events { get; } = new();

    /// <summary>
    /// Filtered data items from the selected event based on EventFilterMode.
    /// </summary>
    public ObservableCollection<string> FilteredEventData { get; } = new();

    /// <summary>
    /// Form model for add/edit observer dialog.
    /// </summary>
    public ObserverFormModel ObserverFormModel { get; } = new();

    // Event list pagination
    [ObservableProperty]
    private int _eventCurrentPage = 1;

    [ObservableProperty]
    private int _eventPageSize = 25;

    public int EventPageCount => Events.Count == 0 ? 1 : (int)Math.Ceiling((double)Events.Count / EventPageSize);
    public ObservableCollection<ObserverEvent> PagedEvents { get; } = new();

    // Detail data pagination
    [ObservableProperty]
    private int _detailCurrentPage = 1;

    [ObservableProperty]
    private int _detailPageSize = 10;

    public int DetailPageCount => _allFilteredData.Count == 0 ? 1 : (int)Math.Ceiling((double)_allFilteredData.Count / DetailPageSize);
    public ObservableCollection<string> PagedFilteredEventData { get; } = new();
    private List<string> _allFilteredData = new();

    public bool HasItems => Items.Count > 0;
    public bool ShowEmptyState => !IsLoading && !HasItems;
    public bool HasEvents => Events.Count > 0;
    public bool HasSelectedObserver => SelectedObserver != null;
    public bool HasSelectedEvent => SelectedEvent != null;

    // Track previous results per observer for manual diffing
    private readonly Dictionary<string, List<string>> _previousResults = new();
    // Track all events per observer (events persist for session even if user switches observers)
    private readonly Dictionary<string, List<ObserverEvent>> _allEvents = new();

    public ObserversViewModel(
        IObserverRepository observerRepository,
        IToastService? toastService = null)
        : base(toastService)
    {
        _observerRepository = observerRepository;
    }

    protected override void OnActivated()
    {
        base.OnActivated();
        _ = LoadObserversAsync();
    }

    /// <summary>
    /// Loads observers from the repository. Called when the view becomes active.
    /// </summary>
    public async Task LoadAsync()
    {
        await LoadObserversAsync();
    }

    private async Task LoadObserversAsync()
    {
        await ExecuteOperationAsync(
            async () =>
            {
                var observers = await _observerRepository.GetObserversAsync();

                Items.Clear();
                foreach (var observer in observers)
                {
                    Items.Add(observer);
                }

                OnPropertyChanged(nameof(HasItems));
                OnPropertyChanged(nameof(ShowEmptyState));
            },
            errorMessage: "Failed to load observers",
            showLoadingState: true);
    }

    [RelayCommand]
    private void SelectObserver(DittoDatabaseObserver? observer)
    {
        SelectedObserver = observer;
        OnPropertyChanged(nameof(HasSelectedObserver));

        // Load events for this observer from session cache
        LoadEventsForSelectedObserver();

        if (observer != null)
        {
            WeakReferenceMessenger.Default.Send(new ListingItemSelectedMessage(observer, "Observer"));
        }
    }

    [RelayCommand]
    private void SelectEvent(ObserverEvent? observerEvent)
    {
        SelectedEvent = observerEvent;
    }

    [RelayCommand]
    private void AddObserver()
    {
        ObserverFormModel.Reset();
        WeakReferenceMessenger.Default.Send(new ShowAddObserverFormMessage());
    }

    [RelayCommand]
    private void EditObserver(DittoDatabaseObserver? observer)
    {
        if (observer == null) return;
        ObserverFormModel.FromObserver(observer);
        WeakReferenceMessenger.Default.Send(new ShowAddObserverFormMessage());
    }

    [RelayCommand]
    private async Task SaveObserverAsync()
    {
        if (!ObserverFormModel.IsValid())
        {
            ShowError(ObserverFormModel.GetValidationError() ?? "Please fill in all required fields.");
            return;
        }

        await ExecuteOperationAsync(
            async () =>
            {
                var observer = ObserverFormModel.ToObserver();
                await _observerRepository.SaveObserverAsync(observer);

                // Check if we're editing (find existing item with same ID) or adding new
                var existingIndex = -1;
                for (int i = 0; i < Items.Count; i++)
                {
                    if (Items[i].Id == observer.Id)
                    {
                        existingIndex = i;
                        break;
                    }
                }

                if (existingIndex >= 0)
                {
                    // Preserve active state when editing
                    var wasActive = Items[existingIndex].IsActive;
                    Items[existingIndex] = observer with { IsActive = wasActive };
                }
                else
                {
                    Items.Add(observer);
                }

                WeakReferenceMessenger.Default.Send(new HideObserverFormMessage());

                OnPropertyChanged(nameof(HasItems));
                OnPropertyChanged(nameof(ShowEmptyState));
            },
            errorMessage: "Failed to save observer",
            showLoadingState: true,
            showSuccessToast: true,
            successMessage: "Observer saved successfully");
    }

    [RelayCommand]
    private async Task DeleteObserverAsync(DittoDatabaseObserver? observer)
    {
        if (observer == null) return;

        await ExecuteOperationAsync(
            async () =>
            {
                await _observerRepository.DeleteObserverAsync(observer.Id);
                Items.Remove(observer);

                // Clean up session data
                _previousResults.Remove(observer.Id);
                _allEvents.Remove(observer.Id);

                // If the deleted observer was selected, clear selection
                if (SelectedObserver?.Id == observer.Id)
                {
                    SelectedObserver = null;
                    Events.Clear();
                    SelectedEvent = null;
                    FilteredEventData.Clear();
                    OnPropertyChanged(nameof(HasSelectedObserver));
                    OnPropertyChanged(nameof(HasEvents));
                    OnPropertyChanged(nameof(HasSelectedEvent));
                }

                OnPropertyChanged(nameof(HasItems));
                OnPropertyChanged(nameof(ShowEmptyState));
            },
            errorMessage: $"Failed to delete observer '{observer.Name}'",
            showLoadingState: true,
            showSuccessToast: true,
            successMessage: $"Observer '{observer.Name}' deleted successfully");
    }

    [RelayCommand]
    private async Task ActivateObserverAsync(DittoDatabaseObserver? observer)
    {
        if (observer == null) return;

        var success = await _observerRepository.ActivateObserverAsync(observer, result =>
        {
            OnObserverCallback(observer.Id, result);
        });

        if (success)
        {
            // Update the item in the list with active state
            var index = Items.IndexOf(observer);
            if (index >= 0)
            {
                Items[index] = observer with { IsActive = true };

                // If this was the selected observer, update selection too
                if (SelectedObserver?.Id == observer.Id)
                {
                    SelectedObserver = Items[index];
                    OnPropertyChanged(nameof(HasSelectedObserver));
                }
            }

            ShowSuccess($"Observer '{observer.Name}' activated");
        }
        else
        {
            ShowError($"Failed to activate observer '{observer.Name}'");
        }
    }

    [RelayCommand]
    private void DeactivateObserver(DittoDatabaseObserver? observer)
    {
        if (observer == null) return;

        _observerRepository.DeactivateObserver(observer.Id);

        // Update the item in the list
        var index = Items.IndexOf(observer);
        if (index >= 0)
        {
            Items[index] = observer with { IsActive = false };

            if (SelectedObserver?.Id == observer.Id)
            {
                SelectedObserver = Items[index];
                OnPropertyChanged(nameof(HasSelectedObserver));
            }
        }

        ShowInfo($"Observer '{observer.Name}' stopped");
    }

    [RelayCommand]
    private void CancelObserverForm()
    {
        WeakReferenceMessenger.Default.Send(new HideObserverFormMessage());
    }

    [RelayCommand]
    private void SetDetailViewMode(string mode)
    {
        DetailViewMode = mode;
    }

    partial void OnDetailViewModeChanged(string value)
    {
        OnPropertyChanged(nameof(IsRawMode));
        OnPropertyChanged(nameof(IsTableMode));
    }

    [RelayCommand]
    private void SetEventFilter(string mode)
    {
        EventFilterMode = mode;
        RefreshFilteredEventData();
    }

    /// <summary>
    /// Callback invoked by DittoStoreObserver when data changes.
    /// Computes diffs manually and creates an ObserverEvent.
    /// </summary>
    private void OnObserverCallback(string observerId, DittoQueryResult result)
    {
        try
        {
            // Extract data as JSON strings
            var currentData = new List<string>();
            foreach (var item in result.Items)
            {
                try
                {
                    currentData.Add(item.JsonString());
                }
                catch
                {
                    currentData.Add("{}");
                }
            }

            // Compute diff against previous results
            _previousResults.TryGetValue(observerId, out var previousData);
            var (insertIndexes, updatedIndexes, deletedIndexes) =
                ComputeDiff(previousData ?? new List<string>(), currentData);

            // Store current as previous for next callback
            _previousResults[observerId] = currentData;

            var observerEvent = new ObserverEvent
            {
                ObserverId = observerId,
                Data = currentData,
                InsertIndexes = insertIndexes,
                UpdatedIndexes = updatedIndexes,
                DeletedIndexes = deletedIndexes,
                EventTime = DateTime.Now
            };

            // Store in session cache
            if (!_allEvents.ContainsKey(observerId))
                _allEvents[observerId] = new List<ObserverEvent>();
            _allEvents[observerId].Add(observerEvent);

            // Update UI on the UI thread if this is the selected observer
            Dispatcher.UIThread.InvokeAsync(() =>
            {
                if (SelectedObserver?.Id == observerId)
                {
                    Events.Add(observerEvent);
                    OnPropertyChanged(nameof(HasEvents));
                    RefreshPagedEvents();
                }
            });

            result.Dispose();
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[ERROR] Observer callback failed: {ex.Message}");
        }
    }

    /// <summary>
    /// Simple diff computation comparing previous and current JSON result sets.
    /// </summary>
    private static (List<int> inserts, List<int> updates, List<int> deletes) ComputeDiff(
        List<string> previous, List<string> current)
    {
        var inserts = new List<int>();
        var updates = new List<int>();
        var deletes = new List<int>();

        // Build a set of previous items for lookup
        var previousSet = new HashSet<string>(previous);
        var currentSet = new HashSet<string>(current);

        // Find inserts and updates in current
        for (int i = 0; i < current.Count; i++)
        {
            if (!previousSet.Contains(current[i]))
            {
                // This item is new - could be insert or update
                // Try to match by _id to distinguish insert from update
                var currentId = ExtractId(current[i]);
                if (currentId != null && previous.Any(p => ExtractId(p) == currentId))
                {
                    updates.Add(i);
                }
                else
                {
                    inserts.Add(i);
                }
            }
        }

        // Find deletes from previous
        for (int i = 0; i < previous.Count; i++)
        {
            var prevId = ExtractId(previous[i]);
            if (prevId != null && !current.Any(c => ExtractId(c) == prevId))
            {
                deletes.Add(i);
            }
            else if (prevId == null && !currentSet.Contains(previous[i]))
            {
                deletes.Add(i);
            }
        }

        return (inserts, updates, deletes);
    }

    /// <summary>
    /// Extracts the _id field from a JSON string for diff comparison.
    /// </summary>
    private static string? ExtractId(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.TryGetProperty("_id", out var idElement))
            {
                return idElement.ToString();
            }
        }
        catch
        {
            // Ignore parse errors
        }
        return null;
    }

    [RelayCommand]
    private void EventNextPage()
    {
        if (EventCurrentPage < EventPageCount) { EventCurrentPage++; RefreshPagedEvents(); }
    }

    [RelayCommand]
    private void EventPreviousPage()
    {
        if (EventCurrentPage > 1) { EventCurrentPage--; RefreshPagedEvents(); }
    }

    [RelayCommand]
    private void DetailNextPage()
    {
        if (DetailCurrentPage < DetailPageCount) { DetailCurrentPage++; RefreshPagedFilteredData(); }
    }

    [RelayCommand]
    private void DetailPreviousPage()
    {
        if (DetailCurrentPage > 1) { DetailCurrentPage--; RefreshPagedFilteredData(); }
    }

    private void RefreshPagedEvents()
    {
        PagedEvents.Clear();
        var skip = (EventCurrentPage - 1) * EventPageSize;
        foreach (var e in Events.Skip(skip).Take(EventPageSize))
            PagedEvents.Add(e);
        OnPropertyChanged(nameof(EventPageCount));
    }

    private void RefreshPagedFilteredData()
    {
        PagedFilteredEventData.Clear();
        var skip = (DetailCurrentPage - 1) * DetailPageSize;
        foreach (var item in _allFilteredData.Skip(skip).Take(DetailPageSize))
            PagedFilteredEventData.Add(item);
        OnPropertyChanged(nameof(DetailPageCount));
    }

    private void LoadEventsForSelectedObserver()
    {
        Events.Clear();
        SelectedEvent = null;
        FilteredEventData.Clear();

        if (SelectedObserver != null && _allEvents.TryGetValue(SelectedObserver.Id, out var events))
        {
            foreach (var e in events)
            {
                Events.Add(e);
            }
        }

        OnPropertyChanged(nameof(HasEvents));
        EventCurrentPage = 1;
        RefreshPagedEvents();
    }

    private void RefreshFilteredEventData()
    {
        _allFilteredData = SelectedEvent == null
            ? new List<string>()
            : EventFilterMode switch
            {
                "inserted" => SelectedEvent.GetInsertedData(),
                "updated" => SelectedEvent.GetUpdatedData(),
                _ => SelectedEvent.Data.ToList()
            };

        DetailCurrentPage = 1;
        RefreshPagedFilteredData();

        FilteredEventData.Clear();
        foreach (var item in _allFilteredData)
        {
            FilteredEventData.Add(item);
        }
    }

    partial void OnSelectedEventChanged(ObserverEvent? value)
    {
        OnPropertyChanged(nameof(HasSelectedEvent));
        RefreshFilteredEventData();
    }

    partial void OnEventFilterModeChanged(string value)
    {
        RefreshFilteredEventData();
        OnPropertyChanged(nameof(IsFilterItems));
        OnPropertyChanged(nameof(IsFilterInserted));
        OnPropertyChanged(nameof(IsFilterUpdated));
    }
}
