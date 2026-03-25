using Avalonia.Controls;
using Avalonia.Interactivity;

namespace EdgeStudio.Views.StudioView.Controls;

public partial class DetailBottomBar : UserControl
{
    public DetailBottomBar()
    {
        InitializeComponent();
    }

    private void CollapseButton_Click(object? sender, RoutedEventArgs e)
    {
        ExpandedBar.IsVisible = false;
        CollapsedBar.IsVisible = true;
    }

    private void ExpandButton_Click(object? sender, RoutedEventArgs e)
    {
        CollapsedBar.IsVisible = false;
        ExpandedBar.IsVisible = true;
    }
}
