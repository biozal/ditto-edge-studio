using System.Threading.Tasks;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Services;
using EdgeStudio.ViewModels;
using FluentAssertions;
using Moq;
using Xunit;

namespace EdgeStudioTests
{
    public class PreferencesViewModelTests
    {
        private readonly Mock<ISettingsRepository> _mockSettings;
        private readonly PreferencesViewModel _vm;

        public PreferencesViewModelTests()
        {
            _mockSettings = new Mock<ISettingsRepository>();
            _vm = new PreferencesViewModel(_mockSettings.Object, null);
        }

        [Fact]
        public async Task LoadSettingsAsync_LoadsValuesFromRepository()
        {
            _mockSettings.Setup(s => s.GetBoolAsync("mcpServerEnabled", false)).ReturnsAsync(true);
            _mockSettings.Setup(s => s.GetIntAsync("mcpServerPort", 65269)).ReturnsAsync(9090);

            await _vm.LoadSettingsAsync();

            _vm.IsMcpServerEnabled.Should().BeTrue();
            _vm.McpServerPort.Should().Be(9090);
        }

        [Fact]
        public async Task LoadSettingsAsync_UsesDefaults_WhenNoSettingsExist()
        {
            _mockSettings.Setup(s => s.GetBoolAsync("mcpServerEnabled", false)).ReturnsAsync(false);
            _mockSettings.Setup(s => s.GetIntAsync("mcpServerPort", 65269)).ReturnsAsync(65269);

            await _vm.LoadSettingsAsync();

            _vm.IsMcpServerEnabled.Should().BeFalse();
            _vm.McpServerPort.Should().Be(65269);
        }

        [Fact]
        public async Task SaveSettingsCommand_PersistsValues()
        {
            _vm.IsMcpServerEnabled = true;
            _vm.McpServerPort = 8080;

            await _vm.SaveSettingsCommand.ExecuteAsync(null);

            _mockSettings.Verify(s => s.SetBoolAsync("mcpServerEnabled", true), Times.Once);
            _mockSettings.Verify(s => s.SetIntAsync("mcpServerPort", 8080), Times.Once);
        }

        [Fact]
        public async Task SaveSettingsCommand_RejectsInvalidPort()
        {
            _vm.McpServerPort = 80;

            await _vm.SaveSettingsCommand.ExecuteAsync(null);

            _mockSettings.Verify(s => s.SetBoolAsync(It.IsAny<string>(), It.IsAny<bool>()), Times.Never);
            _vm.StatusMessage.Should().Contain("Port must be between");
        }
    }
}
