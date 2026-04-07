using Avalonia;
using Avalonia.Controls.Primitives;

namespace EdgeStudio.UI.Controls;

public class DialogItem : TemplatedControl
{
    public static readonly StyledProperty<string> TitleProperty =
        AvaloniaProperty.Register<DialogItem, string>(nameof(Title), defaultValue: "");

    public static readonly StyledProperty<string> MessageProperty =
        AvaloniaProperty.Register<DialogItem, string>(nameof(Message), defaultValue: "");

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
}
