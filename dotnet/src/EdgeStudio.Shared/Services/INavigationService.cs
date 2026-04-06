using EdgeStudio.Shared.Models;

namespace EdgeStudio.Shared.Services;

public interface INavigationService
{
    NavigationItemType CurrentNavigationType { get; }

    void NavigateTo(NavigationItemType navigationType);

    /// <summary>
    /// Updates the current navigation type without sending a NavigationChangedMessage.
    /// Used when views are changed directly (e.g., on database open) to keep the
    /// service state in sync without triggering recursive navigation.
    /// </summary>
    void SetCurrentType(NavigationItemType navigationType);

    // Event converted to WeakReferenceMessenger pattern for better memory management
}
