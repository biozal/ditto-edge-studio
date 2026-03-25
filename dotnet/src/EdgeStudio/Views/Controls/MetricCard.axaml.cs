using Avalonia;
using Avalonia.Controls;

namespace EdgeStudio.Views.Controls;

public partial class MetricCard : UserControl
{
    public static readonly StyledProperty<string> TitleProperty =
        AvaloniaProperty.Register<MetricCard, string>(nameof(Title), string.Empty);
    public static readonly StyledProperty<string> ValueProperty =
        AvaloniaProperty.Register<MetricCard, string>(nameof(Value), "—");
    public static readonly StyledProperty<string?> SubtitleProperty =
        AvaloniaProperty.Register<MetricCard, string?>(nameof(Subtitle));

    public string Title
    {
        get => GetValue(TitleProperty);
        set => SetValue(TitleProperty, value);
    }
    public string Value
    {
        get => GetValue(ValueProperty);
        set => SetValue(ValueProperty, value);
    }
    public string? Subtitle
    {
        get => GetValue(SubtitleProperty);
        set => SetValue(SubtitleProperty, value);
    }

    public MetricCard()
    {
        InitializeComponent();
        PropertyChanged += (_, e) =>
        {
            if (e.Property == TitleProperty) TitleText.Text = (string?)e.NewValue ?? string.Empty;
            else if (e.Property == ValueProperty) ValueText.Text = (string?)e.NewValue ?? "—";
            else if (e.Property == SubtitleProperty)
            {
                SubtitleText.Text = (string?)e.NewValue;
                SubtitleText.IsVisible = !string.IsNullOrEmpty((string?)e.NewValue);
            }
        };
        // Apply initial values
        TitleText.Text = Title;
        ValueText.Text = Value ?? "—";
    }
}
