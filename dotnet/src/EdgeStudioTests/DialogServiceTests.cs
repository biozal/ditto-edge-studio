using Avalonia.Headless.XUnit;
using EdgeStudio.Services;
using EdgeStudio.Shared.Services;
using FluentAssertions;
using Moq;
using SukiUI.Dialogs;
using Xunit;

namespace EdgeStudioTests;

public class DialogServiceTests
{
    private readonly Mock<ISukiDialogManager> _mockDialogManager;
    private readonly IDialogService _dialogService;

    public DialogServiceTests()
    {
        _mockDialogManager = new Mock<ISukiDialogManager>();
        _dialogService = new SukiDialogService(_mockDialogManager.Object);
    }

    [Fact]
    public void Constructor_NullDialogManager_ShouldThrow()
    {
        // Act
        var act = () => new SukiDialogService(null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [AvaloniaFact]
    public void ShowError_ShouldCallTryShowDialogOnManager()
    {
        // Arrange
        _mockDialogManager
            .Setup(m => m.TryShowDialog(It.IsAny<ISukiDialog>()))
            .Returns(true);

        // Act
        _dialogService.ShowError("Test Title", "Test message");

        // Assert
        _mockDialogManager.Verify(
            m => m.TryShowDialog(It.IsAny<ISukiDialog>()),
            Times.Once);
    }
}
