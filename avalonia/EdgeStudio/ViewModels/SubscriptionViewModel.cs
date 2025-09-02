using System.Collections.ObjectModel;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Data.Repositories;
using EdgeStudio.Messages;
using EdgeStudio.Models;

namespace EdgeStudio.ViewModels;

public partial class SubscriptionViewModel : ObservableObject
{
    private readonly ISubscriptionRepository _subscriptionRepository;

    [ObservableProperty]
    private string _listingTitle = "SUBSCRIPTIONS";
    
    [ObservableProperty]
    private string _detailsTitle = "PEERS";
   
    [ObservableProperty]
    private object? _selectedItem;
    
    [ObservableProperty]
    private bool _isLoading;
    
    [ObservableProperty]
    private string? _errorMessage;
    
    [ObservableProperty]
    private bool _showError;
    
    public ObservableCollection<DittoDatabaseSubscription> Items { get; }
    
    /// <summary>
    /// Form model for add/edit subscription dialog
    /// </summary>
    public Models.SubscriptionFormModel SubscriptionFormModel { get; }
    
    public bool HasItems => Items.Count > 0;
    public bool ShowEmptyState => !IsLoading && !HasItems;
    
    // Events converted to WeakReferenceMessenger pattern for better memory management
    
    public SubscriptionViewModel(ISubscriptionRepository subscriptionRepository)
    {
        _subscriptionRepository = subscriptionRepository;
        Items = new ObservableCollection<DittoDatabaseSubscription>();
        SubscriptionFormModel = new Models.SubscriptionFormModel();
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
        try
        {
            IsLoading = true;
            HideError();
            var subscriptions = await _subscriptionRepository.GetDittoSubscriptions();
            
            Items.Clear();
            foreach (var subscription in subscriptions)
            {
                Items.Add(subscription);
            }
        }
        catch (System.Exception ex)
        {
            ShowErrorMessage($"Failed to load subscriptions: {ex.Message}");
        }
        finally
        {
            IsLoading = false;
            OnPropertyChanged(nameof(HasItems));
            OnPropertyChanged(nameof(ShowEmptyState));
        }
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
        // TODO: Open edit subscription dialog
        // For now, placeholder implementation
    }
    
    [RelayCommand]
    private async Task DeleteSubscriptionAsync(DittoDatabaseSubscription subscription)
    {
        if (subscription == null) return;
        
        try
        {
            IsLoading = true;
            HideError();
            await _subscriptionRepository.DeleteDittoSubscription(subscription);
            Items.Remove(subscription);
        }
        catch (System.Exception ex)
        {
            ShowErrorMessage($"Failed to delete subscription '{subscription.Name}': {ex.Message}");
        }
        finally
        {
            IsLoading = false;
            OnPropertyChanged(nameof(HasItems));
            OnPropertyChanged(nameof(ShowEmptyState));
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
    
    [RelayCommand]
    private async Task SaveSubscriptionAsync()
    {
        if (!SubscriptionFormModel.IsValid())
        {
            ShowErrorMessage(SubscriptionFormModel.GetValidationError() ?? "Please fill in all required fields.");
            return;
        }
        
        try
        {
            IsLoading = true;
            HideError();
            
            var subscription = SubscriptionFormModel.ToSubscription();
            await _subscriptionRepository.SaveDittoSubscription(subscription);
            
            Items.Add(subscription);
            WeakReferenceMessenger.Default.Send(new HideSubscriptionFormMessage());
            
            OnPropertyChanged(nameof(HasItems));
            OnPropertyChanged(nameof(ShowEmptyState));
        }
        catch (System.Exception ex)
        {
            ShowErrorMessage($"Failed to save subscription: {ex.Message}");
        }
        finally
        {
            IsLoading = false;
        }
    }
    
    [RelayCommand]
    private void CancelSubscriptionForm()
    {
        WeakReferenceMessenger.Default.Send(new HideSubscriptionFormMessage());
    }
}