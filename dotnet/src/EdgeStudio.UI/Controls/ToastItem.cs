using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using EdgeStudio.UI.Services;

namespace EdgeStudio.UI.Controls;

public class ToastItem : TemplatedControl
{
    public static readonly StyledProperty<string> TitleProperty =
        AvaloniaProperty.Register<ToastItem, string>(nameof(Title), defaultValue: "");

    public static readonly StyledProperty<string> MessageProperty =
        AvaloniaProperty.Register<ToastItem, string>(nameof(Message), defaultValue: "");

    public static readonly StyledProperty<ToastSeverity> SeverityProperty =
        AvaloniaProperty.Register<ToastItem, ToastSeverity>(nameof(Severity), defaultValue: ToastSeverity.Info);

    public string Title
    {
        get => GetValue(TitleProperty);
        set => SetValue(TitleProperty, value);
    }

    public string Message
    {
        get => GetValue(MessageProperty);
        set => SetValue(MessageProperty, value);
    }

    public ToastSeverity Severity
    {
        get => GetValue(SeverityProperty);
        set => SetValue(SeverityProperty, value);
    }
}
