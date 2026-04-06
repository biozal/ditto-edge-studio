using Avalonia.Interactivity;
using SukiUI.Controls;

namespace EdgeStudio.Views.Help;

public partial class QuickstartProgressWindow : SukiWindow
{
    public QuickstartProgressWindow()
    {
        InitializeComponent();
    }

    public void UpdateProgress(double percent, string message)
    {
        Avalonia.Threading.Dispatcher.UIThread.Post(() =>
        {
            ProgressBar.Value = percent;
            StatusText.Text = message;
        });
    }

    public void ShowError(string message)
    {
        Avalonia.Threading.Dispatcher.UIThread.Post(() =>
        {
            StatusText.Text = "Error";
            ErrorText.Text = message;
            ErrorText.IsVisible = true;
            ActionButton.Content = "OK";
        });
    }

    public void ShowComplete()
    {
        Avalonia.Threading.Dispatcher.UIThread.Post(() =>
        {
            ProgressBar.Value = 100;
            StatusText.Text = "Complete";
        });
    }

    private void ActionButton_Click(object? sender, RoutedEventArgs e)
    {
        Close();
    }
}
