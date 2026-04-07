using Avalonia;
using Avalonia.Controls.Primitives;
using EdgeStudio.UI.Services;

namespace EdgeStudio.UI.Controls;

public class DialogHost : TemplatedControl
{
    public static readonly StyledProperty<DialogManager?> ManagerProperty =
        AvaloniaProperty.Register<DialogHost, DialogManager?>(nameof(Manager));

    public DialogManager? Manager
    {
        get => GetValue(ManagerProperty);
        set => SetValue(ManagerProperty, value);
    }
}
