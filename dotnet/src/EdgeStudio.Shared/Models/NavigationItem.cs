using Material.Icons;

namespace EdgeStudio.Shared.Models;

public enum NavigationItemType
{
    Subscriptions,
    Query,
    Observers,
    Tools
}

public class NavigationItem
{
    public NavigationItemType Type { get; init; }
    public string Label { get; init; } = string.Empty;
    public MaterialIconKind IconKind { get; init; }
    public string Tooltip { get; init; } = string.Empty;

    public static NavigationItem[] AllItems { get; } = new[]
    {
        new NavigationItem
        {
            Type = NavigationItemType.Subscriptions,
            Label = "Subscriptions",
            IconKind = MaterialIconKind.Sync,
            Tooltip = "Sync"
        },
        new NavigationItem
        {
            Type = NavigationItemType.Query,
            Label = "Query",
            IconKind = MaterialIconKind.Database,
            Tooltip = "Query database"
        },
        new NavigationItem
        {
            Type = NavigationItemType.Observers,
            Label = "Observers",
            IconKind = MaterialIconKind.Eye,
            Tooltip = "Observable events"
        },
        new NavigationItem
        {
            Type = NavigationItemType.Tools,
            Label = "Tools",
            IconKind = MaterialIconKind.Tools,
            Tooltip = "Database tools"
        }
    };
}
