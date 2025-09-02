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
    private NavigationItemViewModel? _selectedItem;
    
    public ObservableCollection<NavigationItemViewModel> NavigationItems { get; }
    
    public NavigationItemViewModel? SelectedItem
    {
        get => _selectedItem;
        private set
        {
            if (_selectedItem != value)
            {
                // Clear previous selection
                if (_selectedItem != null)
                    _selectedItem.IsSelected = false;
                
                _selectedItem = value;
                
                // Set new selection
                if (_selectedItem != null)
                    _selectedItem.IsSelected = true;
                
                OnPropertyChanged();
            }
        }
    }
    
    public NavigationViewModel(INavigationService navigationService)
    {
        _navigationService = navigationService;
        
        // Create ViewModels for all navigation items
        NavigationItems = new ObservableCollection<NavigationItemViewModel>(
            NavigationItem.AllItems.Select(item => new NavigationItemViewModel(item)));
        
        // Set initial selection to Subscriptions
        SelectedItem = NavigationItems.FirstOrDefault(x => x.Type == NavigationItemType.Subscriptions);
    }
    
    [RelayCommand]
    private void SelectNavigationItem(NavigationItemViewModel? item)
    {
        if (item != null && item != SelectedItem)
        {
            SelectedItem = item;
            _navigationService.NavigateTo(item.Type);
        }
    }
}