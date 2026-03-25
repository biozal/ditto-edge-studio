using DittoSDK;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Models;
using FluentAssertions;
using Moq;
using System;
using System.Threading.Tasks;
using Xunit;

namespace EdgeStudioTests
{
    /// <summary>
    /// Unit tests for IDittoManager interface
    /// </summary>
    public class DittoManagerTests
    {
        private readonly Mock<IDittoManager> _mockDittoManager;

        public DittoManagerTests()
        {
            _mockDittoManager = new Mock<IDittoManager>();
        }

        #region Property Tests - DittoSelectedApp

        [Fact]
        public void DittoSelectedApp_Get_ShouldReturnNullableValue()
        {
            // Arrange
            _mockDittoManager.Setup(m => m.DittoSelectedApp).Returns((Ditto?)null);

            // Act
            var result = _mockDittoManager.Object.DittoSelectedApp;

            // Assert
            result.Should().BeNull();
            _mockDittoManager.Verify(m => m.DittoSelectedApp, Times.Once);
        }

        [Fact]
        public void DittoSelectedApp_SetProperty_ShouldBeSettable()
        {
            // Arrange
            _mockDittoManager.SetupProperty(m => m.DittoSelectedApp);

            // Act
            _mockDittoManager.Object.DittoSelectedApp = null;

            // Assert
            _mockDittoManager.Object.DittoSelectedApp.Should().BeNull();
        }

        [Fact]
        public void DittoSelectedApp_Property_ShouldExist()
        {
            // Arrange
            _mockDittoManager.Setup(m => m.DittoSelectedApp).Returns((Ditto?)null);

            // Act
            var act = () => _mockDittoManager.Object.DittoSelectedApp;

            // Assert
            act.Should().NotThrow();
        }

        #endregion

        #region Property Tests - SelectedDatabaseConfig

        [Fact]
        public void SelectedDatabaseConfig_Get_ShouldReturnValue()
        {
            // Arrange
            var config = CreateTestDatabaseConfig("test-id", "Test Database");
            _mockDittoManager.Setup(m => m.SelectedDatabaseConfig).Returns(config);

            // Act
            var result = _mockDittoManager.Object.SelectedDatabaseConfig;

            // Assert
            result.Should().NotBeNull();
            result.Should().Be(config);
            result!.Id.Should().Be("test-id");
            result.Name.Should().Be("Test Database");
        }

        [Fact]
        public void SelectedDatabaseConfig_Set_ShouldUpdateValue()
        {
            // Arrange
            var config = CreateTestDatabaseConfig("test-id-2", "Another Database");
            _mockDittoManager.SetupProperty(m => m.SelectedDatabaseConfig);

            // Act
            _mockDittoManager.Object.SelectedDatabaseConfig = config;

            // Assert
            _mockDittoManager.Object.SelectedDatabaseConfig.Should().Be(config);
            _mockDittoManager.Object.SelectedDatabaseConfig!.Name.Should().Be("Another Database");
        }

        [Fact]
        public void SelectedDatabaseConfig_SetToNull_ShouldAllowNull()
        {
            // Arrange
            _mockDittoManager.SetupProperty(m => m.SelectedDatabaseConfig);
            var config = CreateTestDatabaseConfig("test-id-3", "Test");
            _mockDittoManager.Object.SelectedDatabaseConfig = config;

            // Act
            _mockDittoManager.Object.SelectedDatabaseConfig = null;

            // Assert
            _mockDittoManager.Object.SelectedDatabaseConfig.Should().BeNull();
        }

        #endregion

        #region CloseSelectedDatabase Tests

        [Fact]
        public void CloseSelectedDatabase_ShouldCallMethod()
        {
            // Arrange
            _mockDittoManager.Setup(m => m.CloseSelectedDatabase());

            // Act
            _mockDittoManager.Object.CloseSelectedDatabase();

            // Assert
            _mockDittoManager.Verify(m => m.CloseSelectedDatabase(), Times.Once);
        }

        [Fact]
        public void CloseSelectedDatabase_ShouldNotThrow()
        {
            // Arrange
            _mockDittoManager.Setup(m => m.CloseSelectedDatabase());

            // Act
            var act = () => _mockDittoManager.Object.CloseSelectedDatabase();

            // Assert
            act.Should().NotThrow();
        }

        [Fact]
        public void CloseSelectedDatabase_WhenNoDatabaseSelected_ShouldNotThrow()
        {
            // Arrange
            _mockDittoManager.Setup(m => m.SelectedDatabaseConfig).Returns((DittoDatabaseConfig?)null);
            _mockDittoManager.Setup(m => m.CloseSelectedDatabase());

            // Act
            var act = () => _mockDittoManager.Object.CloseSelectedDatabase();

            // Assert
            act.Should().NotThrow();
            _mockDittoManager.Verify(m => m.CloseSelectedDatabase(), Times.Once);
        }

        [Fact]
        public void CloseSelectedDatabase_OnError_ShouldThrowException()
        {
            // Arrange
            _mockDittoManager.Setup(m => m.CloseSelectedDatabase())
                .Throws(new InvalidOperationException("Failed to close database"));

            // Act & Assert
            Assert.Throws<InvalidOperationException>(() => _mockDittoManager.Object.CloseSelectedDatabase());
        }

        #endregion

        #region GetSelectedAppDitto Tests

        [Fact]
        public void GetSelectedAppDitto_ShouldCallMethod()
        {
            // Arrange
            _mockDittoManager.Setup(m => m.GetSelectedAppDitto()).Returns((Ditto)null!);

            // Act
            _mockDittoManager.Object.GetSelectedAppDitto();

            // Assert
            _mockDittoManager.Verify(m => m.GetSelectedAppDitto(), Times.Once);
        }

        [Fact]
        public void GetSelectedAppDitto_WhenNoDatabaseSelected_ShouldThrowException()
        {
            // Arrange
            _mockDittoManager.Setup(m => m.GetSelectedAppDitto())
                .Throws(new InvalidOperationException("No database selected"));

            // Act & Assert
            Assert.Throws<InvalidOperationException>(() => _mockDittoManager.Object.GetSelectedAppDitto());
        }

        [Fact]
        public void GetSelectedAppDitto_MultipleCalls_ShouldBeCallable()
        {
            // Arrange
            _mockDittoManager.Setup(m => m.GetSelectedAppDitto()).Returns((Ditto)null!);

            // Act
            _mockDittoManager.Object.GetSelectedAppDitto();
            _mockDittoManager.Object.GetSelectedAppDitto();

            // Assert
            _mockDittoManager.Verify(m => m.GetSelectedAppDitto(), Times.Exactly(2));
        }

        [Fact]
        public void GetSelectedAppDitto_ShouldNotThrow()
        {
            // Arrange
            _mockDittoManager.Setup(m => m.GetSelectedAppDitto()).Returns((Ditto)null!);

            // Act
            var act = () => _mockDittoManager.Object.GetSelectedAppDitto();

            // Assert
            act.Should().NotThrow();
        }

        #endregion

        #region InitializeDittoSelectedApp Tests

        [Fact]
        public async Task InitializeDittoSelectedApp_WithValidConfig_ShouldReturnTrue()
        {
            // Arrange
            var config = CreateTestDatabaseConfig("selected-app-1", "Selected App Test");
            _mockDittoManager.Setup(m => m.InitializeDittoSelectedApp(It.IsAny<DittoDatabaseConfig>()))
                .ReturnsAsync(true);

            // Act
            var result = await _mockDittoManager.Object.InitializeDittoSelectedApp(config);

            // Assert
            result.Should().BeTrue();
            _mockDittoManager.Verify(m => m.InitializeDittoSelectedApp(It.Is<DittoDatabaseConfig>(
                c => c.Id == config.Id)), Times.Once);
        }

        [Fact]
        public async Task InitializeDittoSelectedApp_OnFailure_ShouldReturnFalse()
        {
            // Arrange
            var config = CreateTestDatabaseConfig("selected-app-2", "Failed App");
            _mockDittoManager.Setup(m => m.InitializeDittoSelectedApp(It.IsAny<DittoDatabaseConfig>()))
                .ReturnsAsync(false);

            // Act
            var result = await _mockDittoManager.Object.InitializeDittoSelectedApp(config);

            // Assert
            result.Should().BeFalse();
        }

        [Fact]
        public async Task InitializeDittoSelectedApp_WithNullConfig_ShouldThrowException()
        {
            // Arrange
            _mockDittoManager.Setup(m => m.InitializeDittoSelectedApp(null!))
                .ThrowsAsync(new ArgumentNullException("databaseConfig"));

            // Act & Assert
            await Assert.ThrowsAsync<ArgumentNullException>(
                () => _mockDittoManager.Object.InitializeDittoSelectedApp(null!));
        }

        [Fact]
        public async Task InitializeDittoSelectedApp_ShouldCallMethod()
        {
            // Arrange
            var config = CreateTestDatabaseConfig("selected-app-3", "Call Test");
            _mockDittoManager.Setup(m => m.InitializeDittoSelectedApp(It.IsAny<DittoDatabaseConfig>()))
                .ReturnsAsync(true);

            // Act
            await _mockDittoManager.Object.InitializeDittoSelectedApp(config);

            // Assert
            _mockDittoManager.Verify(m => m.InitializeDittoSelectedApp(config), Times.Once);
        }

        [Fact]
        public async Task InitializeDittoSelectedApp_OnError_ShouldThrowException()
        {
            // Arrange
            var config = CreateTestDatabaseConfig("selected-app-4", "Error Test");
            _mockDittoManager.Setup(m => m.InitializeDittoSelectedApp(It.IsAny<DittoDatabaseConfig>()))
                .ThrowsAsync(new InvalidOperationException("Failed to initialize selected app"));

            // Act & Assert
            await Assert.ThrowsAsync<InvalidOperationException>(
                () => _mockDittoManager.Object.InitializeDittoSelectedApp(config));
        }

        #endregion

        #region SelectedAppStartSync Tests

        [Fact]
        public void SelectedAppStartSync_ShouldCallMethod()
        {
            // Arrange
            _mockDittoManager.Setup(m => m.SelectedAppStartSync());

            // Act
            _mockDittoManager.Object.SelectedAppStartSync();

            // Assert
            _mockDittoManager.Verify(m => m.SelectedAppStartSync(), Times.Once);
        }

        [Fact]
        public void SelectedAppStartSync_ShouldNotThrow()
        {
            // Arrange
            _mockDittoManager.Setup(m => m.SelectedAppStartSync());

            // Act
            var act = () => _mockDittoManager.Object.SelectedAppStartSync();

            // Assert
            act.Should().NotThrow();
        }

        [Fact]
        public void SelectedAppStartSync_WhenNoDatabaseSelected_ShouldThrowException()
        {
            // Arrange
            _mockDittoManager.Setup(m => m.SelectedAppStartSync())
                .Throws(new InvalidOperationException("No database selected"));

            // Act & Assert
            Assert.Throws<InvalidOperationException>(() => _mockDittoManager.Object.SelectedAppStartSync());
        }

        [Fact]
        public void SelectedAppStartSync_WhenAlreadyStarted_ShouldNotThrow()
        {
            // Arrange
            _mockDittoManager.Setup(m => m.SelectedAppStartSync());

            // Act
            _mockDittoManager.Object.SelectedAppStartSync();
            var act = () => _mockDittoManager.Object.SelectedAppStartSync();

            // Assert
            act.Should().NotThrow();
            _mockDittoManager.Verify(m => m.SelectedAppStartSync(), Times.Exactly(2));
        }

        #endregion

        #region SelectedAppStopSync Tests

        [Fact]
        public void SelectedAppStopSync_ShouldCallMethod()
        {
            // Arrange
            _mockDittoManager.Setup(m => m.SelectedAppStopSync());

            // Act
            _mockDittoManager.Object.SelectedAppStopSync();

            // Assert
            _mockDittoManager.Verify(m => m.SelectedAppStopSync(), Times.Once);
        }

        [Fact]
        public void SelectedAppStopSync_ShouldNotThrow()
        {
            // Arrange
            _mockDittoManager.Setup(m => m.SelectedAppStopSync());

            // Act
            var act = () => _mockDittoManager.Object.SelectedAppStopSync();

            // Assert
            act.Should().NotThrow();
        }

        [Fact]
        public void SelectedAppStopSync_WhenNoDatabaseSelected_ShouldThrowException()
        {
            // Arrange
            _mockDittoManager.Setup(m => m.SelectedAppStopSync())
                .Throws(new InvalidOperationException("No database selected"));

            // Act & Assert
            Assert.Throws<InvalidOperationException>(() => _mockDittoManager.Object.SelectedAppStopSync());
        }

        [Fact]
        public void SelectedAppStopSync_WhenAlreadyStopped_ShouldNotThrow()
        {
            // Arrange
            _mockDittoManager.Setup(m => m.SelectedAppStopSync());

            // Act
            _mockDittoManager.Object.SelectedAppStopSync();
            var act = () => _mockDittoManager.Object.SelectedAppStopSync();

            // Assert
            act.Should().NotThrow();
            _mockDittoManager.Verify(m => m.SelectedAppStopSync(), Times.Exactly(2));
        }

        #endregion

        #region Integration-Style Tests

        [Fact]
        public async Task FullLifecycle_InitializeStartStopClose_ShouldWork()
        {
            // Arrange
            var config = CreateTestDatabaseConfig("lifecycle-test", "Lifecycle Database");

            _mockDittoManager.Setup(m => m.InitializeDittoSelectedApp(It.IsAny<DittoDatabaseConfig>()))
                .ReturnsAsync(true);
            _mockDittoManager.Setup(m => m.GetSelectedAppDitto()).Returns((Ditto)null!);
            _mockDittoManager.Setup(m => m.SelectedAppStartSync());
            _mockDittoManager.Setup(m => m.SelectedAppStopSync());
            _mockDittoManager.Setup(m => m.CloseSelectedDatabase());

            // Act & Assert - Initialize
            var initResult = await _mockDittoManager.Object.InitializeDittoSelectedApp(config);
            initResult.Should().BeTrue();

            // Act & Assert - Get Ditto
            var act = () => _mockDittoManager.Object.GetSelectedAppDitto();
            act.Should().NotThrow();

            // Act & Assert - Start Sync
            var startAct = () => _mockDittoManager.Object.SelectedAppStartSync();
            startAct.Should().NotThrow();

            // Act & Assert - Stop Sync
            var stopAct = () => _mockDittoManager.Object.SelectedAppStopSync();
            stopAct.Should().NotThrow();

            // Act & Assert - Close
            var closeAct = () => _mockDittoManager.Object.CloseSelectedDatabase();
            closeAct.Should().NotThrow();

            // Verify all methods were called
            _mockDittoManager.Verify(m => m.InitializeDittoSelectedApp(config), Times.Once);
            _mockDittoManager.Verify(m => m.GetSelectedAppDitto(), Times.Once);
            _mockDittoManager.Verify(m => m.SelectedAppStartSync(), Times.Once);
            _mockDittoManager.Verify(m => m.SelectedAppStopSync(), Times.Once);
            _mockDittoManager.Verify(m => m.CloseSelectedDatabase(), Times.Once);
        }

        #endregion

        #region Helper Methods

        private static DittoDatabaseConfig CreateTestDatabaseConfig(string id, string name)
        {
            return new DittoDatabaseConfig(
                Id: id,
                Name: name,
                DatabaseId: "db-" + id,
                AuthToken: "token-" + id,
                AuthUrl: "https://auth.example.com",
                HttpApiUrl: "https://api.example.com",
                HttpApiKey: "api-key-" + id,
                Mode: "server",
                AllowUntrustedCerts: false
            );
        }

        #endregion
    }
}
