using System.Collections.Generic;

namespace EdgeStudio.Shared.Services;

public interface ILoggingService
{
    void Debug(string message);
    void Info(string message);
    void Warning(string message);
    void Error(string message);
    IReadOnlyList<string> GetLogFilePaths();
    string GetCombinedLogs();
    void ClearAllLogs();
}
