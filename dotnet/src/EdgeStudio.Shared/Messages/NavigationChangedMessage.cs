using EdgeStudio.Shared.Models;

namespace EdgeStudio.Shared.Messages;

public class NavigationChangedMessage(NavigationItemType navigationType)
{
    public NavigationItemType NavigationType { get; } = navigationType;
}
