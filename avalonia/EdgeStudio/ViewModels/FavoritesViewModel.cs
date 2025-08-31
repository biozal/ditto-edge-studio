using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Messages;

namespace EdgeStudio.ViewModels;

public partial class FavoritesViewModel : ObservableObject
{
    [ObservableProperty]
    private string _listingTitle = "Favorites Listing";
    
    [ObservableProperty]
    private object? _selectedItem;
    
    public ObservableCollection<string> Items { get; }
    
    public FavoritesViewModel()
    {
        Items = new ObservableCollection<string>();
        // Placeholder items for now
        Items.Add("Favorite Query 1");
        Items.Add("Favorite Query 2");
        Items.Add("Favorite Query 3");
    }
    
    [RelayCommand]
    private void SelectItem(object? item)
    {
        SelectedItem = item;
        if (item != null)
        {
            WeakReferenceMessenger.Default.Send(new ListingItemSelectedMessage(item, "Favorite"));
        }
    }
}