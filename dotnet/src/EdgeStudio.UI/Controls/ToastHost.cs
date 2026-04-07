using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using EdgeStudio.UI.Services;

namespace EdgeStudio.UI.Controls;

public class ToastHost : TemplatedControl
{
    public static readonly StyledProperty<ToastManager?> ManagerProperty =
        AvaloniaProperty.Register<ToastHost, ToastManager?>(nameof(Manager));

    public ToastManager? Manager
    {
        get => GetValue(ManagerProperty);
        set => SetValue(ManagerProperty, value);
    }
}
