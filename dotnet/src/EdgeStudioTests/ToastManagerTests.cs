using Avalonia.Headless.XUnit;
using EdgeStudio.UI.Services;
using FluentAssertions;

namespace EdgeStudioTests;

public class ToastManagerTests
{
    [AvaloniaFact]
    public void ShowError_ShouldAddToastToActiveToasts()
    {
        var manager = new ToastManager();
        manager.ShowError("Something failed");
        manager.ActiveToasts.Should().HaveCount(1);
        manager.ActiveToasts[0].Title.Should().Be("Error");
        manager.ActiveToasts[0].Message.Should().Be("Something failed");
        manager.ActiveToasts[0].Severity.Should().Be(ToastSeverity.Error);
    }

    [AvaloniaFact]
    public void ShowSuccess_ShouldAddToastWithCorrectSeverity()
    {
        var manager = new ToastManager();
        manager.ShowSuccess("Done!");
        manager.ActiveToasts.Should().HaveCount(1);
        manager.ActiveToasts[0].Severity.Should().Be(ToastSeverity.Success);
    }

    [AvaloniaFact]
    public void ShowWarning_ShouldAddToastWithCorrectSeverity()
    {
        var manager = new ToastManager();
        manager.ShowWarning("Watch out");
        manager.ActiveToasts.Should().HaveCount(1);
        manager.ActiveToasts[0].Severity.Should().Be(ToastSeverity.Warning);
    }

    [AvaloniaFact]
    public void ShowInfo_ShouldAddToastWithCorrectSeverity()
    {
        var manager = new ToastManager();
        manager.ShowInfo("FYI");
        manager.ActiveToasts.Should().HaveCount(1);
        manager.ActiveToasts[0].Severity.Should().Be(ToastSeverity.Info);
    }

    [AvaloniaFact]
    public void ShowError_WithCustomTitle_ShouldUseCustomTitle()
    {
        var manager = new ToastManager();
        manager.ShowError("msg", "Custom Title");
        manager.ActiveToasts[0].Title.Should().Be("Custom Title");
    }

    [AvaloniaFact]
    public void MaxFiveToasts_ShouldRemoveOldestWhenExceeded()
    {
        var manager = new ToastManager();
        for (int i = 0; i < 6; i++)
        {
            manager.ShowInfo($"Toast {i}");
        }

        manager.ActiveToasts.Should().HaveCount(5);
        manager.ActiveToasts[0].Message.Should().Be("Toast 1");
    }

    [AvaloniaFact]
    public void DismissToast_ShouldRemoveFromActiveToasts()
    {
        var manager = new ToastManager();
        manager.ShowError("msg");
        var toastId = manager.ActiveToasts[0].Id;

        manager.Dismiss(toastId);

        manager.ActiveToasts.Should().BeEmpty();
    }

    [AvaloniaFact]
    public void DismissToast_WithInvalidId_ShouldNotThrow()
    {
        var manager = new ToastManager();
        var act = () => manager.Dismiss(Guid.NewGuid());
        act.Should().NotThrow();
    }
}
