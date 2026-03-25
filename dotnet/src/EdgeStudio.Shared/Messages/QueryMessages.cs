using EdgeStudio.Shared.Models;

namespace EdgeStudio.Shared.Messages
{
    /// <summary>Sent after a query is executed successfully (or with results).</summary>
    public record QueryExecutedMessage(string QueryText, QueryExecutionResult Result);

    /// <summary>Sent when a history/favorites item is clicked — loads query into the active editor.</summary>
    public record LoadQueryRequestedMessage(string QueryText);

    /// <summary>Sent when the user chooses "Add to Favorites" from a history item's context menu.</summary>
    public record AddToFavoritesMessage(QueryHistory Item);

    /// <summary>Sent when the user double-clicks a history/favorites item — loads AND executes the query.</summary>
    public record LoadAndExecuteQueryRequestedMessage(string QueryText);

    /// <summary>Sent when the user double-clicks a result document — triggers inspector to open and show JSON Viewer.</summary>
    public record DocumentDoubleClickedMessage(string Json);

    /// <summary>Sent to navigate the inspector panel to the JSON Viewer tab.</summary>
    public record NavigateInspectorToJsonViewerMessage();
}
