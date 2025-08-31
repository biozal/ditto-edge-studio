namespace EdgeStudio.Models;

public enum NavigationItemType
{
    Subscriptions,
    Collections,
    History,
    Favorites,
    Indexes,
    Observers,
    Tools
}

public class NavigationItem
{
    public NavigationItemType Type { get; init; }
    public string Label { get; init; } = string.Empty;
    public string Icon { get; init; } = string.Empty;
    public string Tooltip { get; init; } = string.Empty;
    
    public static NavigationItem[] AllItems { get; } = new[]
    {
        new NavigationItem 
        { 
            Type = NavigationItemType.Subscriptions, 
            Label = "Subscriptions", 
            Icon = "sync", 
            Tooltip = "Manage subscriptions" 
        },
        new NavigationItem 
        { 
            Type = NavigationItemType.Collections, 
            Label = "Collections", 
            Icon = "folder", 
            Tooltip = "Browse collections" 
        },
        new NavigationItem 
        { 
            Type = NavigationItemType.History, 
            Label = "History", 
            Icon = "history", 
            Tooltip = "Query history" 
        },
        new NavigationItem 
        { 
            Type = NavigationItemType.Favorites, 
            Label = "Favorites", 
            Icon = "star", 
            Tooltip = "Favorite queries" 
        },
        new NavigationItem 
        { 
            Type = NavigationItemType.Indexes, 
            Label = "Indexes", 
            Icon = "database", 
            Tooltip = "Database indexes" 
        },
        new NavigationItem 
        { 
            Type = NavigationItemType.Observers, 
            Label = "Observers", 
            Icon = "visibility", 
            Tooltip = "Observable events" 
        },
        new NavigationItem 
        { 
            Type = NavigationItemType.Tools, 
            Label = "Tools", 
            Icon = "build", 
            Tooltip = "Database tools" 
        }
    };
}