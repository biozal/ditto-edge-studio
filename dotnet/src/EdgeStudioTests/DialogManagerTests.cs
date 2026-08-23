using Avalonia.Headless.XUnit;
using EdgeStudio.UI.Services;
using FluentAssertions;

namespace EdgeStudioTests;

public class DialogManagerTests
{
    [AvaloniaFact]
    public void ShowError_ShouldSetCurrentDialogAndIsOpen()
    {
        var manager = new DialogManager();
        manager.ShowError("Error Title", "Something broke");

        manager.CurrentDialog.Should().NotBeNull();
        manager.CurrentDialog!.Title.Should().Be("Error Title");
        manager.CurrentDialog.Message.Should().Be("Something broke");
        manager.IsOpen.Should().BeTrue();
    }

    [AvaloniaFact]
    public void Dismiss_ShouldClearCurrentDialogAndIsOpen()
    {
        var manager = new DialogManager();
        manager.ShowError("Title", "Message");

        manager.Dismiss();

        manager.CurrentDialog.Should().BeNull();
        manager.IsOpen.Should().BeFalse();
    }

    [AvaloniaFact]
    public void ShowError_WhenDialogAlreadyOpen_ShouldReplaceIt()
    {
        var manager = new DialogManager();
        manager.ShowError("First", "First message");
        manager.ShowError("Second", "Second message");

        manager.CurrentDialog!.Title.Should().Be("Second");
    }

    [AvaloniaFact]
    public void ShowConfirmation_ShouldReturnTrueWhenConfirmed()
    {
        var manager = new DialogManager();
        var task = manager.ShowConfirmationAsync("Confirm?", "Are you sure?", "Yes", "No");

        manager.CurrentDialog.Should().NotBeNull();
        manager.IsOpen.Should().BeTrue();

        // Simulate user clicking confirm
        manager.CurrentDialog!.Buttons[0].Callback();

        task.IsCompleted.Should().BeTrue();
        task.Result.Should().BeTrue();
        manager.IsOpen.Should().BeFalse();
    }

    [AvaloniaFact]
    public void ShowConfirmation_ShouldReturnFalseWhenCancelled()
    {
        var manager = new DialogManager();
        var task = manager.ShowConfirmationAsync("Confirm?", "Are you sure?", "Yes", "No");

        // Simulate user clicking cancel
        manager.CurrentDialog!.Buttons[1].Callback();

        task.IsCompleted.Should().BeTrue();
        task.Result.Should().BeFalse();
    }

    [AvaloniaFact]
    public void InitialState_ShouldHaveNoDialogAndNotOpen()
    {
        var manager = new DialogManager();
        manager.CurrentDialog.Should().BeNull();
        manager.IsOpen.Should().BeFalse();
    }
}
