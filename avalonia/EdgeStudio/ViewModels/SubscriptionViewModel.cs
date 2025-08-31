using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Messages;

namespace EdgeStudio.ViewModels;

public partial class SubscriptionViewModel : ObservableObject
{
    [ObservableProperty]
    private string _listingTitle = "Subscription List";
    
    [ObservableProperty]
    private string _detailsTitle = "Subscription Details";
    
    [ObservableProperty]
    private object? _selectedItem;
    
    public ObservableCollection<string> Items { get; }
    
    public SubscriptionViewModel()
    {
        Items = new ObservableCollection<string>();
        // Placeholder items for now
        Items.Add("Subscription 1");
        Items.Add("Subscription 2");
        Items.Add("Subscription 3");
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
}