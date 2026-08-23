using Avalonia.Controls;
using Avalonia.Headless.XUnit;
using Avalonia.Input;
using EdgeStudio.UI.Controls;
using FluentAssertions;

namespace EdgeStudioTests;

public class GlassCardTests
{
    [AvaloniaFact]
    public void GlassCard_DefaultCornerRadius_ShouldBe8()
    {
        var card = new GlassCard();
        card.CornerRadius.TopLeft.Should().Be(8);
    }

    [AvaloniaFact]
    public void GlassCard_IsInteractive_DefaultFalse()
    {
        var card = new GlassCard();
        card.IsInteractive.Should().BeFalse();
    }

    [AvaloniaFact]
    public void GlassCard_SetCornerRadius_ShouldApply()
    {
        var card = new GlassCard { CornerRadius = new Avalonia.CornerRadius(12) };
        card.CornerRadius.TopLeft.Should().Be(12);
    }

    [AvaloniaFact]
    public void GlassCard_ContentPresenter_ShouldRenderContent()
    {
        var card = new GlassCard
        {
            Content = new TextBlock { Text = "Test" }
        };

        card.Content.Should().NotBeNull();
        card.Content.Should().BeOfType<TextBlock>();
    }
}
