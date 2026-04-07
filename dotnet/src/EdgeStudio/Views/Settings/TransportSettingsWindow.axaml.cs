using Avalonia.Interactivity;
using EdgeStudio.ViewModels;

namespace EdgeStudio.Views.Settings;

public partial class TransportSettingsWindow : Window
{
    // Required by Avalonia AXAML compiler
    public TransportSettingsWindow()
    {
        InitializeComponent();
    }

    public TransportSettingsWindow(SubscriptionSettingsViewModel vm) : this()
    {
        DataContext = vm;
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
