using System;
using System.Collections.Generic;
using System.IO;
using Serilog;

namespace EdgeStudio.Shared.Services;

public sealed class SerilogLoggingService : ILoggingService, IDisposable
{
    private readonly ILogger _logger;
    private readonly string _logsDirectory;
    private bool _disposed;

    public SerilogLoggingService()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        _logsDirectory = Path.Combine(appData, "EdgeStudio", "logs");
        Directory.CreateDirectory(_logsDirectory);

        var logPath = Path.Combine(_logsDirectory, "log-.txt");

        _logger = new LoggerConfiguration()
            .MinimumLevel.Debug()
            .WriteTo.File(
                logPath,
                rollingInterval: RollingInterval.Day,
                retainedFileCountLimit: 7,
                fileSizeLimitBytes: 5 * 1024 * 1024,
                rollOnFileSizeLimit: true,
                outputTemplate: "{Timestamp:yyyy-MM-dd HH:mm:ss.fff} [{Level:u3}] {Message:lj}{NewLine}{Exception}")
            .CreateLogger();
    }

    public void Debug(string message) => _logger.Debug(message);
    public void Info(string message) => _logger.Information(message);
    public void Warning(string message) => _logger.Warning(message);
    public void Error(string message) => _logger.Error(message);

    public IReadOnlyList<string> GetLogFilePaths()
    {
        if (!Directory.Exists(_logsDirectory))
            return Array.Empty<string>();
        return Directory.GetFiles(_logsDirectory, "log-*.txt");
    }

    public string GetCombinedLogs()
    {
        var files = GetLogFilePaths();
        if (files.Count == 0) return string.Empty;

        var parts = new List<string>();
        foreach (var file in files)
        {
            try { parts.Add(File.ReadAllText(file)); }
            catch { /* skip unreadable files */ }
        }
        return string.Join(Environment.NewLine, parts);
    }

    public void ClearAllLogs()
    {
        foreach (var file in GetLogFilePaths())
        {
            try { File.Delete(file); }
            catch { /* skip */ }
        }
    }

    public void Dispose()
    {
        if (!_disposed)
        {
            (_logger as IDisposable)?.Dispose();
            _disposed = true;
        }
    }
}
