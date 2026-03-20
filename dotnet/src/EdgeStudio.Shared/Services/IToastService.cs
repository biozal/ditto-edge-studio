using System;

namespace EdgeStudio.Shared.Services;

/// <summary>
/// Service for displaying toast notifications to the user.
/// Provides a platform-agnostic abstraction over the underlying notification system.
/// </summary>
public interface IToastService
{
    /// <summary>
    /// Displays an error toast notification with a 5 second duration.
    /// </summary>
    /// <param name="message">The error message to display</param>
    /// <param name="title">Optional title for the toast (defaults to "Error")</param>
    void ShowError(string message, string? title = null);

    /// <summary>
    /// Displays a success toast notification with a 3 second duration.
    /// </summary>
    /// <param name="message">The success message to display</param>
    /// <param name="title">Optional title for the toast (defaults to "Success")</param>
    void ShowSuccess(string message, string? title = null);

    /// <summary>
    /// Displays a warning toast notification with a 4 second duration.
    /// </summary>
    /// <param name="message">The warning message to display</param>
    /// <param name="title">Optional title for the toast (defaults to "Warning")</param>
    void ShowWarning(string message, string? title = null);

    /// <summary>
    /// Displays an informational toast notification with a 4 second duration.
    /// </summary>
    /// <param name="message">The informational message to display</param>
    /// <param name="title">Optional title for the toast (defaults to "Information")</param>
    void ShowInfo(string message, string? title = null);
}
