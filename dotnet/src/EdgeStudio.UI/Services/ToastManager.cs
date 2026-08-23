using System;
using System.Collections.ObjectModel;
using System.Linq;
using Avalonia.Threading;
using EdgeStudio.Shared.Services;

namespace EdgeStudio.UI.Services;

public class ToastManager : IToastService
{
    private const int MaxToasts = 5;

    public ObservableCollection<ToastItemData> ActiveToasts { get; } = new();

    public void ShowError(string message, string? title = null)
    {
        AddToast(title ?? "Error", message, ToastSeverity.Error, TimeSpan.FromSeconds(5));
    }

    public void ShowSuccess(string message, string? title = null)
    {
        AddToast(title ?? "Success", message, ToastSeverity.Success, TimeSpan.FromSeconds(3));
    }

    public void ShowWarning(string message, string? title = null)
    {
        AddToast(title ?? "Warning", message, ToastSeverity.Warning, TimeSpan.FromSeconds(4));
    }

    public void ShowInfo(string message, string? title = null)
    {
        AddToast(title ?? "Information", message, ToastSeverity.Info, TimeSpan.FromSeconds(4));
    }

    public void Dismiss(Guid toastId)
    {
        DispatchToUI(() =>
        {
            var toast = ActiveToasts.FirstOrDefault(t => t.Id == toastId);
            if (toast != null)
            {
                ActiveToasts.Remove(toast);
            }
        });
    }

    private void AddToast(string title, string message, ToastSeverity severity, TimeSpan duration)
    {
        DispatchToUI(() =>
        {
            var toast = new ToastItemData(Guid.NewGuid(), title, message, severity, duration);

            while (ActiveToasts.Count >= MaxToasts)
            {
                ActiveToasts.RemoveAt(0);
            }

            ActiveToasts.Add(toast);
            StartAutoDismiss(toast);
        });
    }

    private void StartAutoDismiss(ToastItemData toast)
    {
        var timer = new DispatcherTimer { Interval = toast.Duration };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            Dismiss(toast.Id);
        };
        timer.Start();
    }

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
