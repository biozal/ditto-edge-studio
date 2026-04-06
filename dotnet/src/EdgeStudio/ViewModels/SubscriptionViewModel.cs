using System.Collections.ObjectModel;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Shared.Data.Repositories;
using EdgeStudio.Shared.Messages;
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;

namespace EdgeStudio.ViewModels;

public partial class SubscriptionViewModel : LoadableViewModelBase
{
    private readonly ISubscriptionRepository _subscriptionRepository;

    [ObservableProperty]
    private string _listingTitle = "SUBSCRIPTIONS";

    [ObservableProperty]
    private string _detailsTitle = "PEERS";

    [ObservableProperty]
    private object? _selectedItem;

    public ObservableCollection<DittoDatabaseSubscription> Items { get; }

    /// <summary>
    /// Form model for add/edit subscription dialog
    /// </summary>
    public SubscriptionFormModel SubscriptionFormModel { get; }

    public bool HasItems => Items.Count > 0;
    public bool ShowEmptyState => !IsLoading && !HasItems;

    public SubscriptionViewModel(ISubscriptionRepository subscriptionRepository, IToastService? toastService = null)
        : base(toastService)
    {
        _subscriptionRepository = subscriptionRepository;
        Items = new ObservableCollection<DittoDatabaseSubscription>();
        Items.CollectionChanged += (_, _) =>
        {
            OnPropertyChanged(nameof(HasItems));
            OnPropertyChanged(nameof(ShowEmptyState));
        };
        SubscriptionFormModel = new SubscriptionFormModel();
    }

    /// <summary>
    /// Called when the view becomes active - load subscriptions
    /// </summary>
    protected override void OnActivated()
    {
        base.OnActivated();
        _ = LoadSubscriptionsAsync();
    }

    /// <summary>
    /// Loads subscriptions from the repository. Should be called by the View when it's displayed.
    /// </summary>
    public async Task LoadAsync()
    {
        await LoadSubscriptionsAsync();
    }
    
    private async Task LoadSubscriptionsAsync()
    {
        await ExecuteOperationAsync(
            async () =>
            {
                var subscriptions = await _subscriptionRepository.GetDittoSubscriptions();

                Items.Clear();
                foreach (var subscription in subscriptions)
                {
                    Items.Add(subscription);
                }

                OnPropertyChanged(nameof(HasItems));
                OnPropertyChanged(nameof(ShowEmptyState));
            },
            errorMessage: "Failed to load subscriptions",
            showLoadingState: true);
    }
    
    [RelayCommand]
    private void SelectItem(object? item)
    {
        SelectedItem = item;
        if (item != null)
        {
            WeakReferenceMessenger.Default.Send(new ListingItemSelectedMessage(item, "Subscription"));
        }
    }
    
    [RelayCommand]
    private void AddSubscription()
    {
        SubscriptionFormModel.Reset();
        WeakReferenceMessenger.Default.Send(new ShowAddSubscriptionFormMessage());
    }
    
    [RelayCommand]
    private void EditSubscription(DittoDatabaseSubscription subscription)
    {
        if (subscription == null) return;

        // Populate the form with the subscription data
        SubscriptionFormModel.FromSubscription(subscription);

        // Show the form (same form as add, but with data pre-filled)
        WeakReferenceMessenger.Default.Send(new ShowAddSubscriptionFormMessage());
    }
    
    [RelayCommand]
    private async Task DeleteSubscriptionAsync(DittoDatabaseSubscription subscription)
    {
        if (subscription == null) return;

        await ExecuteOperationAsync(
            async () =>
            {
                await _subscriptionRepository.DeleteDittoSubscription(subscription);
                Items.Remove(subscription);

                OnPropertyChanged(nameof(HasItems));
                OnPropertyChanged(nameof(ShowEmptyState));
            },
            errorMessage: $"Failed to delete subscription '{subscription.Name}'",
            showLoadingState: true,
            showSuccessToast: true,
            successMessage: $"Subscription '{subscription.Name}' deleted successfully");
    }
    
    [RelayCommand]
    private async Task SaveSubscriptionAsync()
    {
        if (!SubscriptionFormModel.IsValid())
        {
            ShowError(SubscriptionFormModel.GetValidationError() ?? "Please fill in all required fields.");
            return;
        }

        await ExecuteOperationAsync(
            async () =>
            {
                var subscription = SubscriptionFormModel.ToSubscription();
                await _subscriptionRepository.SaveDittoSubscription(subscription);

                // Check if we're editing (find existing item with same ID) or adding new
                var existingIndex = -1;
                for (int i = 0; i < Items.Count; i++)
                {
                    if (Items[i].Id == subscription.Id)
                    {
                        existingIndex = i;
                        break;
                    }
                }

                if (existingIndex >= 0)
                {
                    // Update existing item
                    Items[existingIndex] = subscription;
                }
                else
                {
                    // Add new item
                    Items.Add(subscription);
                }

                WeakReferenceMessenger.Default.Send(new HideSubscriptionFormMessage());

                OnPropertyChanged(nameof(HasItems));
                OnPropertyChanged(nameof(ShowEmptyState));
            },
            errorMessage: "Failed to save subscription",
            showLoadingState: true,
            showSuccessToast: true,
            successMessage: "Subscription saved successfully");
    }
    
    [RelayCommand]
    private void CancelSubscriptionForm()
    {
        WeakReferenceMessenger.Default.Send(new HideSubscriptionFormMessage());
    }
}