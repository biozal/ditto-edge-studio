using Avalonia.Threading;
using EdgeStudio.Shared.Services;
using SukiUI.Toasts;
using System;

namespace EdgeStudio.Services;

/// <summary>
/// Toast service implementation using SukiUI's toast notification system.
/// Ensures all toast operations are executed on the UI thread.
/// </summary>
public class SukiToastService : IToastService
{
    private readonly ISukiToastManager _toastManager;

    public SukiToastService(ISukiToastManager toastManager)
    {
        _toastManager = toastManager ?? throw new ArgumentNullException(nameof(toastManager));
    }

    public void ShowError(string message, string? title = null)
    {
        DispatchToUI(() =>
        {
            _toastManager
                .CreateToast()
                .WithTitle(title ?? "Error")
                .WithContent(message)
                .Dismiss().After(TimeSpan.FromSeconds(5))
                .Dismiss().ByClicking()
                .Queue();
        });
    }

    public void ShowSuccess(string message, string? title = null)
    {
        DispatchToUI(() =>
        {
            _toastManager
                .CreateToast()
                .WithTitle(title ?? "Success")
                .WithContent(message)
                .Dismiss().After(TimeSpan.FromSeconds(3))
                .Dismiss().ByClicking()
                .Queue();
        });
    }

    public void ShowWarning(string message, string? title = null)
    {
        DispatchToUI(() =>
        {
            _toastManager
                .CreateToast()
                .WithTitle(title ?? "Warning")
                .WithContent(message)
                .Dismiss().After(TimeSpan.FromSeconds(4))
                .Dismiss().ByClicking()
                .Queue();
        });
    }

    public void ShowInfo(string message, string? title = null)
    {
        DispatchToUI(() =>
        {
            _toastManager
                .CreateToast()
                .WithTitle(title ?? "Info")
                .WithContent(message)
                .Dismiss().After(TimeSpan.FromSeconds(4))
                .Dismiss().ByClicking()
                .Queue();
        });
    }

    /// <summary>
    /// Ensures the action is executed on the UI thread
    /// </summary>
    private static void DispatchToUI(Action action)
    {
        if (Dispatcher.UIThread.CheckAccess())
        {
            action();
        }
        else
        {
            Dispatcher.UIThread.Post(action);
        }
    }
}
