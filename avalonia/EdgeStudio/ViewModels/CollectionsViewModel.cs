using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Messages;

namespace EdgeStudio.ViewModels;

public partial class CollectionsViewModel : ObservableObject
{
    [ObservableProperty]
    private string _listingTitle = "Collection Listing";
    
    [ObservableProperty]
    private object? _selectedItem;
    
    public ObservableCollection<string> Items { get; }
    
    public CollectionsViewModel()
    {
        Items = new ObservableCollection<string>();
        // Placeholder items for now
        Items.Add("Collection 1");
        Items.Add("Collection 2");
        Items.Add("Collection 3");
    }
    
    [RelayCommand]
    private void SelectItem(object? item)
    {
        SelectedItem = item;
        if (item != null)
        {
            WeakReferenceMessenger.Default.Send(new ListingItemSelectedMessage(item, "Collection"));
        }
    }
}