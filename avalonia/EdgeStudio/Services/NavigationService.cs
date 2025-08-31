using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Messages;
using EdgeStudio.Models;
using System;

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
                NavigationChanged?.Invoke(this, value);
                WeakReferenceMessenger.Default.Send(new NavigationChangedMessage(value));
            }
        }
    }
    
    public event EventHandler<NavigationItemType>? NavigationChanged;
    
    public void NavigateTo(NavigationItemType navigationType)
    {
        CurrentNavigationType = navigationType;
    }
}