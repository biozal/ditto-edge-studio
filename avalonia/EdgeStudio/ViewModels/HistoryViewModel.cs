using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Messages;

namespace EdgeStudio.ViewModels;

public partial class HistoryViewModel : ObservableObject
{
    [ObservableProperty]
    private string _listingTitle = "History Listing";
    
    [ObservableProperty]
    private object? _selectedItem;
    
    public ObservableCollection<string> Items { get; }
    
    public HistoryViewModel()
    {
        Items = new ObservableCollection<string>();
        // Placeholder items for now
        Items.Add("Query from 2 hours ago");
        Items.Add("Query from yesterday");
        Items.Add("Query from last week");
    }
    
    [RelayCommand]
    private void SelectItem(object? item)
    {
        SelectedItem = item;
        if (item != null)
        {
            WeakReferenceMessenger.Default.Send(new ListingItemSelectedMessage(item, "History"));
        }
    }
}