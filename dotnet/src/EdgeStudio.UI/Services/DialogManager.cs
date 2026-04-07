using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using Avalonia.Threading;
using EdgeStudio.Shared.Services;

namespace EdgeStudio.UI.Services;

public class DialogManager : IDialogService, INotifyPropertyChanged
{
    private DialogItemData? _currentDialog;
    private bool _isOpen;

    public DialogItemData? CurrentDialog
    {
        get => _currentDialog;
        private set
        {
            _currentDialog = value;
            OnPropertyChanged();
        }
    }

    public bool IsOpen
    {
        get => _isOpen;
        private set
        {
            _isOpen = value;
            OnPropertyChanged();
        }
    }

    public void ShowError(string title, string message)
    {
        DispatchToUI(() =>
        {
            CurrentDialog = new DialogItemData(
                title,
                message,
                DialogSeverity.Error,
                new List<DialogButton>
                {
                    new("OK", Dismiss)
                });
            IsOpen = true;
        });
    }

    public Task<bool> ShowConfirmationAsync(
        string title,
        string message,
        string confirmLabel = "OK",
        string cancelLabel = "Cancel")
    {
        var tcs = new TaskCompletionSource<bool>();
        DispatchToUI(() =>
        {
            CurrentDialog = new DialogItemData(
                title,
                message,
                DialogSeverity.Warning,
                new List<DialogButton>
                {
                    new(confirmLabel, () =>
                    {
                        Dismiss();
                        tcs.TrySetResult(true);
                    }),
                    new(cancelLabel, () =>
                    {
                        Dismiss();
                        tcs.TrySetResult(false);
                    })
                });
            IsOpen = true;
        });
        return tcs.Task;
    }

    public void Dismiss()
    {
        DispatchToUI(() =>
        {
            CurrentDialog = null;
            IsOpen = false;
        });
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
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
