using Material.Icons;

namespace EdgeStudio.Shared.Models;

public enum NavigationItemType
{
    Subscriptions,
    Query,
    Observers,
    Logging,
    AppMetrics,
    QueryMetrics
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
            Tooltip = "Subscriptions"
        },
        new NavigationItem
        {
            Type = NavigationItemType.Query,
            Label = "Query",
            IconKind = MaterialIconKind.Database,
            Tooltip = "Query"
        },
        new NavigationItem
        {
            Type = NavigationItemType.Observers,
            Label = "Observers",
            IconKind = MaterialIconKind.Eye,
            Tooltip = "Observers"
        },
        new NavigationItem
        {
            Type = NavigationItemType.Logging,
            Label = "Logging",
            IconKind = MaterialIconKind.FormatListBulleted,
            Tooltip = "Logging"
        },
        new NavigationItem
        {
            Type = NavigationItemType.AppMetrics,
            Label = "App Metrics",
            IconKind = MaterialIconKind.ChartBar,
            Tooltip = "App Metrics"
        },
        new NavigationItem
        {
            Type = NavigationItemType.QueryMetrics,
            Label = "Query Metrics",
            IconKind = MaterialIconKind.ChartLine,
            Tooltip = "Query Metrics"
        }
    };
}
