using Avalonia.Headless.XUnit;
using EdgeStudio.UI.Services;
using FluentAssertions;

namespace EdgeStudioTests;

public class DialogServiceTests
{
    [AvaloniaFact]
    public void ShowError_ShouldSetCurrentDialogAndIsOpen()
    {
        var dialogManager = new DialogManager();
        dialogManager.ShowError("Test Title", "Test message");

        dialogManager.CurrentDialog.Should().NotBeNull();
        dialogManager.CurrentDialog!.Title.Should().Be("Test Title");
        dialogManager.IsOpen.Should().BeTrue();
    }

    [AvaloniaFact]
    public void ShowError_ShouldHaveOkButton()
    {
        var dialogManager = new DialogManager();
        dialogManager.ShowError("Title", "Message");

        dialogManager.CurrentDialog!.Buttons.Should().HaveCount(1);
        dialogManager.CurrentDialog.Buttons[0].Label.Should().Be("OK");
    }
}
