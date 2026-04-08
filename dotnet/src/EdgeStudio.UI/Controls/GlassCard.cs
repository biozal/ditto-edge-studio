using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Media;

namespace EdgeStudio.UI.Controls;

public class GlassCard : ContentControl
{
    public static readonly StyledProperty<bool> IsInteractiveProperty =
        AvaloniaProperty.Register<GlassCard, bool>(nameof(IsInteractive), defaultValue: false);

    public static readonly new StyledProperty<CornerRadius> CornerRadiusProperty =
        AvaloniaProperty.Register<GlassCard, CornerRadius>(nameof(CornerRadius), defaultValue: new CornerRadius(8));

    static GlassCard()
    {
        // Ensure hit testing works even if no Background resource resolves
        BackgroundProperty.OverrideDefaultValue<GlassCard>(Brushes.Transparent);
    }

    public bool IsInteractive
    {
        get => GetValue(IsInteractiveProperty);
        set => SetValue(IsInteractiveProperty, value);
    }

    public new CornerRadius CornerRadius
    {
        get => GetValue(CornerRadiusProperty);
        set => SetValue(CornerRadiusProperty, value);
    }

    protected override void OnPointerEntered(PointerEventArgs e)
    {
        base.OnPointerEntered(e);
        if (IsInteractive)
        {
            PseudoClasses.Set(":pointerover", true);
        }
    }

    protected override void OnPointerExited(PointerEventArgs e)
    {
        base.OnPointerExited(e);
        if (IsInteractive)
        {
            PseudoClasses.Set(":pointerover", false);
            PseudoClasses.Set(":pressed", false);
        }
    }

    protected override void OnPointerPressed(PointerPressedEventArgs e)
    {
        base.OnPointerPressed(e);
        if (IsInteractive)
        {
            PseudoClasses.Set(":pressed", true);
        }
    }

    protected override void OnPointerReleased(PointerReleasedEventArgs e)
    {
        base.OnPointerReleased(e);
        if (IsInteractive)
        {
            PseudoClasses.Set(":pressed", false);
        }
    }
}
