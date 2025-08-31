using EdgeStudio.Models;
using System;

namespace EdgeStudio.Services;

public interface INavigationService
{
    NavigationItemType CurrentNavigationType { get; }
    
    void NavigateTo(NavigationItemType navigationType);
    
    event EventHandler<NavigationItemType>? NavigationChanged;
}