using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Interactivity;
using CommunityToolkit.Mvvm.ComponentModel;
using EdgeStudio.Shared.Services;
using Material.Icons;
using SukiUI.Controls;

namespace EdgeStudio.Views.Help;

/// <summary>
/// ViewModel for an individual quickstart project row in the browser list.
/// </summary>
public partial class QuickstartProjectViewModel : ObservableObject
{
    [ObservableProperty]
    private string _name = string.Empty;

    [ObservableProperty]
    private string _directoryName = string.Empty;

    [ObservableProperty]
    private string _path = string.Empty;

    [ObservableProperty]
    private bool _isConfigured;

    /// <summary>
    /// Material icon kind indicating whether the project has been auto-configured.
    /// </summary>
    public MaterialIconKind StatusIcon =>
        IsConfigured ? MaterialIconKind.CheckCircleOutline : MaterialIconKind.FolderOutline;
}

/// <summary>
/// Window that lists downloaded Ditto quickstart projects with paths and copy actions.
/// </summary>
public partial class QuickstartBrowserWindow : SukiWindow
{
    public QuickstartBrowserWindow()
    {
        InitializeComponent();
    }

    /// <summary>
    /// Parameterized constructor used by the download flow.
    /// </summary>
    /// <param name="projects">Discovered quickstart projects to display.</param>
    /// <param name="directoryPath">Root directory path shown in the header.</param>
    /// <param name="isConfigured">Whether the projects were auto-configured with credentials.</param>
    public QuickstartBrowserWindow(
        List<QuickstartProject> projects,
        string directoryPath,
        bool isConfigured)
    {
        InitializeComponent();

        PathText.Text = directoryPath;

        ProjectList.ItemsSource = projects
            .Select(p => new QuickstartProjectViewModel
            {
                Name = p.Name,
                DirectoryName = p.DirectoryName,
                Path = p.Path,
                IsConfigured = isConfigured
            })
            .ToList();

        WarningBanner.IsVisible = !isConfigured;
    }

    private void Done_Click(object? sender, RoutedEventArgs e)
    {
        Close();
    }

    private async void CopyPath_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is Button button && button.Tag is string path)
        {
            var clipboard = TopLevel.GetTopLevel(this)?.Clipboard;
            if (clipboard != null)
            {
                await clipboard.SetTextAsync(path);

                // Brief visual feedback: swap to a checkmark icon for 1.5 s
                var originalContent = button.Content;
                button.Content = new Avalonia.Controls.TextBlock { Text = "✓" };
                await Task.Delay(1500);
                button.Content = originalContent;
            }
        }
    }
}
