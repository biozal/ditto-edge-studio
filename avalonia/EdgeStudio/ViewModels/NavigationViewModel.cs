using System.Collections.ObjectModel;
using System.Linq;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using EdgeStudio.Models;
using EdgeStudio.Services;

namespace EdgeStudio.ViewModels;

public partial class NavigationViewModel : ObservableObject
{
    private readonly INavigationService _navigationService;
    
    [ObservableProperty]
    private NavigationItem? _selectedItem;
    
    public ObservableCollection<NavigationItem> NavigationItems { get; }
    
    public NavigationViewModel(INavigationService navigationService)
    {
        _navigationService = navigationService;
        NavigationItems = new ObservableCollection<NavigationItem>(NavigationItem.AllItems);
        
        // Set initial selection to Subscriptions
        SelectedItem = NavigationItems.FirstOrDefault(x => x.Type == NavigationItemType.Subscriptions);
    }
    
    [RelayCommand]
    private void SelectNavigationItem(NavigationItem? item)
    {
        if (item != null && item != SelectedItem)
        {
            SelectedItem = item;
            _navigationService.NavigateTo(item.Type);
        }
    }
}