using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.VisualTree;

namespace EdgeStudio.Views.StudioView.Controls;

public partial class DetailBottomBar : UserControl
{
    public DetailBottomBar()
    {
        InitializeComponent();
    }

    private void ExpandedBar_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        // Walk up the visual tree from the click target — if it hits an interactive
        // control (button, combobox, toggle) let that control handle it instead.
        var hit = e.Source as Avalonia.Visual;
        while (hit != null && hit != ExpandedBar)
        {
            if (hit is Button or ComboBox or ToggleButton)
                return;
            hit = hit.GetVisualParent();
        }

        ExpandedBar.IsVisible = false;
        CollapsedBar.IsVisible = true;
    }

    private void CollapsedBar_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        CollapsedBar.IsVisible = false;
        ExpandedBar.IsVisible = true;
    }
}
