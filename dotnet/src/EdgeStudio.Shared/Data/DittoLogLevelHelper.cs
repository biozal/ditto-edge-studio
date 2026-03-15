using DittoSDK;

namespace EdgeStudio.Shared.Data;

/// <summary>
/// Converts log level strings (as stored in DittoDatabaseConfig.LogLevel) to DittoLogLevel values.
/// Single place of truth — eliminates duplicated switch expressions across DittoManager and UI ViewModels.
/// </summary>
public static class DittoLogLevelHelper
{
    public static DittoLogLevel Parse(string? level) => level switch
    {
        "error"   => DittoLogLevel.Error,
        "warning" => DittoLogLevel.Warning,
        "debug"   => DittoLogLevel.Debug,
        "verbose" => DittoLogLevel.Verbose,
        _         => DittoLogLevel.Info,
    };
}
