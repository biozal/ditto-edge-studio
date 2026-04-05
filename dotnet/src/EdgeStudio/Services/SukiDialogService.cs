using Avalonia.Controls.Notifications;
using Avalonia.Threading;
using EdgeStudio.Shared.Services;
using SukiUI.Dialogs;
using System;

namespace EdgeStudio.Services;

/// <summary>
/// Dialog service implementation using SukiUI's dialog system.
/// Ensures all dialog operations are executed on the UI thread.
/// </summary>
public class SukiDialogService : IDialogService
{
    private readonly ISukiDialogManager _dialogManager;

    public SukiDialogService(ISukiDialogManager dialogManager)
    {
        _dialogManager = dialogManager ?? throw new ArgumentNullException(nameof(dialogManager));
    }

    public void ShowError(string title, string message)
    {
        DispatchToUI(() =>
        {
            var builder = _dialogManager.CreateDialog();
            builder.SetType(NotificationType.Error);
            builder.SetTitle(title);
            builder.SetContent(message);
            builder.AddActionButton("OK", _ => { }, dismissOnClick: true, classes: []);
            builder.TryShow();
        });
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
