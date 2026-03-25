using System;

namespace EdgeStudio.Models.Logging;

public enum AppLogLevel
{
    Verbose,
    Debug,
    Info,
    Warning,
    Error
}

public enum LogComponent
{
    All,
    Sync,
    Store,
    Query,
    Observer,
    Transport,
    Auth,
    Other
}

public enum LogEntrySource
{
    DittoSDK,
    Application
}

public record LogEntry(
    Guid Id,
    DateTimeOffset Timestamp,
    AppLogLevel Level,
    string Message,
    LogComponent Component,
    LogEntrySource Source,
    string RawLine
)
{
    public string LevelAbbreviation => Level switch
    {
        AppLogLevel.Error   => "ERR",
        AppLogLevel.Warning => "WARN",
        AppLogLevel.Info    => "INFO",
        AppLogLevel.Debug   => "DBG",
        AppLogLevel.Verbose => "VERB",
        _                   => "???"
    };

    /// <summary>Foreground hex color for the level badge (matches SwiftUI levelColor).</summary>
    public string LevelForegroundHex => Level switch
    {
        AppLogLevel.Error   => "#F44336",
        AppLogLevel.Warning => "#FF9800",
        AppLogLevel.Info    => "#2196F3",
        _                   => "#9E9E9E"
    };

    /// <summary>Semi-transparent background hex for the level badge (18 % opacity tint).</summary>
    public string LevelBackgroundHex => Level switch
    {
        AppLogLevel.Error   => "#30F44336",
        AppLogLevel.Warning => "#30FF9800",
        AppLogLevel.Info    => "#302196F3",
        _                   => "#22808080"
    };

    /// <summary>Show the component pill only when the component carries meaningful info.</summary>
    public bool IsComponentVisible =>
        Component != LogComponent.Other && Component != LogComponent.All;

    public static LogComponent DetectComponent(string message)
    {
        var lower = message.ToLowerInvariant();
        if (lower.Contains("sync") || lower.Contains("replication")) return LogComponent.Sync;
        if (lower.Contains("store") || lower.Contains("storage"))    return LogComponent.Store;
        if (lower.Contains("query") || lower.Contains("dql"))        return LogComponent.Query;
        if (lower.Contains("observe") || lower.Contains("observer")) return LogComponent.Observer;
        if (lower.Contains("transport") || lower.Contains("bluetooth") ||
            lower.Contains("wifi") || lower.Contains("websocket"))   return LogComponent.Transport;
        if (lower.Contains("auth") || lower.Contains("token") ||
            lower.Contains("login"))                                  return LogComponent.Auth;
        return LogComponent.Other;
    }
}
