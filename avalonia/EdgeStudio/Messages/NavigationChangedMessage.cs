using EdgeStudio.Models;

namespace EdgeStudio.Messages;

public class NavigationChangedMessage
{
    public NavigationItemType NavigationType { get; }
    
    public NavigationChangedMessage(NavigationItemType navigationType)
    {
        NavigationType = navigationType;
    }
}