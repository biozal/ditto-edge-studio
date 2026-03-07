using System;
using Avalonia.Controls;
using Avalonia.Interactivity;
using EdgeStudio.Shared.Models;

namespace EdgeStudio.Views.Controls;

public partial class DetailBottomBar : UserControl
{
    public DetailBottomBar()
    {
        InitializeComponent();
        DataContextChanged += OnDataContextChanged;
    }

    private void OnDataContextChanged(object? sender, EventArgs e)
    {
        UpdateBindings();
    }

    private void UpdateBindings()
    {
        if (DataContext is not ConnectionsByTransport connections) return;

        ConnectionCountText.Text = connections.TotalConnections.ToString();
        TransportsList.IsVisible = connections.HasActiveConnections;
        NoConnectionsPanel.IsVisible = !connections.HasActiveConnections;
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
