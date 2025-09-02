using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Messages;
using EdgeStudio.Models;

namespace EdgeStudio.Services;

public class NavigationService : INavigationService
{
    private NavigationItemType _currentNavigationType = NavigationItemType.Collections;
    
    public NavigationItemType CurrentNavigationType 
    { 
        get => _currentNavigationType;
        private set
        {
            if (_currentNavigationType != value)
            {
                _currentNavigationType = value;
                WeakReferenceMessenger.Default.Send(new NavigationChangedMessage(value));
            }
        }
    }
    
    // Event converted to WeakReferenceMessenger pattern for better memory management
    
    public void NavigateTo(NavigationItemType navigationType)
    {
        CurrentNavigationType = navigationType;
    }
}