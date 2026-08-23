using System;

namespace EdgeStudio.UI.Services;

public enum ToastSeverity
{
    Error,
    Success,
    Warning,
    Info
}

public record ToastItemData(
    Guid Id,
    string Title,
    string Message,
    ToastSeverity Severity,
    TimeSpan Duration);
