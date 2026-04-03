using Avalonia.Interactivity;
using EdgeStudio.ViewModels;
using SukiUI.Controls;

namespace EdgeStudio.Views.Settings;

public partial class PreferencesWindow : SukiWindow
{
    // Required by Avalonia AXAML compiler
    public PreferencesWindow()
    {
        InitializeComponent();
    }

    public PreferencesWindow(PreferencesViewModel vm) : this()
    {
        DataContext = vm;
    }

    private void Close_Click(object? sender, RoutedEventArgs e) => Close();
}
