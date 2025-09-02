using EdgeStudio.Models;

namespace EdgeStudio.Services;

public interface INavigationService
{
    NavigationItemType CurrentNavigationType { get; }
    
    void NavigateTo(NavigationItemType navigationType);
    
    // Event converted to WeakReferenceMessenger pattern for better memory management
}