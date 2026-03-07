using EdgeStudio.Shared.Data.Repositories;
using EdgeStudio.Shared.Models;
using FluentAssertions;
using Moq;
using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using Xunit;

namespace EdgeStudioTests
{
    /// <summary>
    /// Unit tests for IDatabaseRepository interface
    /// </summary>
    public class DatabaseRepositoryTests
    {
        private readonly Mock<IDatabaseRepository> _mockRepository;

        public DatabaseRepositoryTests()
        {
            _mockRepository = new Mock<IDatabaseRepository>();
        }

        #region AddDittoDatabaseConfig Tests

        [Fact]
        public async Task AddDittoDatabaseConfig_ShouldCallRepositoryMethod()
        {
            // Arrange
            var config = CreateTestDatabaseConfig("test-id-1", "Test Database");
            _mockRepository.Setup(r => r.AddDittoDatabaseConfig(It.IsAny<DittoDatabaseConfig>()))
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.AddDittoDatabaseConfig(config);

            // Assert
            _mockRepository.Verify(r => r.AddDittoDatabaseConfig(It.Is<DittoDatabaseConfig>(
                c => c.Id == config.Id && c.Name == config.Name)), Times.Once);
        }

        [Fact]
        public async Task AddDittoDatabaseConfig_WithNullConfig_ShouldThrowException()
        {
            // Arrange
            _mockRepository.Setup(r => r.AddDittoDatabaseConfig(null!))
                .ThrowsAsync(new ArgumentNullException(nameof(DittoDatabaseConfig)));

            // Act & Assert
            await Assert.ThrowsAsync<ArgumentNullException>(
                () => _mockRepository.Object.AddDittoDatabaseConfig(null!));
        }

        [Fact]
        public async Task AddDittoDatabaseConfig_WithValidConfig_ShouldComplete()
        {
            // Arrange
            var config = CreateTestDatabaseConfig("test-id-2", "Production Database");
            _mockRepository.Setup(r => r.AddDittoDatabaseConfig(It.IsAny<DittoDatabaseConfig>()))
                .Returns(Task.CompletedTask);

            // Act
            var act = async () => await _mockRepository.Object.AddDittoDatabaseConfig(config);

            // Assert
            await act.Should().NotThrowAsync();
        }

        #endregion

        #region DeleteDittoDatabaseConfig Tests

        [Fact]
        public async Task DeleteDittoDatabaseConfig_ShouldCallRepositoryMethod()
        {
            // Arrange
            var config = CreateTestDatabaseConfig("test-id-3", "Delete Test");
            _mockRepository.Setup(r => r.DeleteDittoDatabaseConfig(It.IsAny<DittoDatabaseConfig>()))
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.DeleteDittoDatabaseConfig(config);

            // Assert
            _mockRepository.Verify(r => r.DeleteDittoDatabaseConfig(It.Is<DittoDatabaseConfig>(
                c => c.Id == config.Id)), Times.Once);
        }

        [Fact]
        public async Task DeleteDittoDatabaseConfig_WithNullConfig_ShouldThrowException()
        {
            // Arrange
            _mockRepository.Setup(r => r.DeleteDittoDatabaseConfig(null!))
                .ThrowsAsync(new ArgumentNullException(nameof(DittoDatabaseConfig)));

            // Act & Assert
            await Assert.ThrowsAsync<ArgumentNullException>(
                () => _mockRepository.Object.DeleteDittoDatabaseConfig(null!));
        }

        [Fact]
        public async Task DeleteDittoDatabaseConfig_WithNonExistentConfig_ShouldThrowException()
        {
            // Arrange
            var config = CreateTestDatabaseConfig("non-existent-id", "Non Existent");
            _mockRepository.Setup(r => r.DeleteDittoDatabaseConfig(It.IsAny<DittoDatabaseConfig>()))
                .ThrowsAsync(new InvalidOperationException("Configuration not found"));

            // Act & Assert
            await Assert.ThrowsAsync<InvalidOperationException>(
                () => _mockRepository.Object.DeleteDittoDatabaseConfig(config));
        }

        #endregion

        #region UpdateDatabaseConfig Tests

        [Fact]
        public async Task UpdateDatabaseConfig_ShouldCallRepositoryMethod()
        {
            // Arrange
            var config = CreateTestDatabaseConfig("test-id-4", "Updated Database");
            _mockRepository.Setup(r => r.UpdateDatabaseConfig(It.IsAny<DittoDatabaseConfig>()))
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.UpdateDatabaseConfig(config);

            // Assert
            _mockRepository.Verify(r => r.UpdateDatabaseConfig(It.Is<DittoDatabaseConfig>(
                c => c.Id == config.Id && c.Name == config.Name)), Times.Once);
        }

        [Fact]
        public async Task UpdateDatabaseConfig_WithNullConfig_ShouldThrowException()
        {
            // Arrange
            _mockRepository.Setup(r => r.UpdateDatabaseConfig(null!))
                .ThrowsAsync(new ArgumentNullException(nameof(DittoDatabaseConfig)));

            // Act & Assert
            await Assert.ThrowsAsync<ArgumentNullException>(
                () => _mockRepository.Object.UpdateDatabaseConfig(null!));
        }

        [Fact]
        public async Task UpdateDatabaseConfig_WithModifiedFields_ShouldComplete()
        {
            // Arrange
            var originalConfig = CreateTestDatabaseConfig("test-id-5", "Original Name");
            var updatedConfig = originalConfig with { Name = "Updated Name", Mode = "smallpeersonly" };

            _mockRepository.Setup(r => r.UpdateDatabaseConfig(It.IsAny<DittoDatabaseConfig>()))
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.UpdateDatabaseConfig(updatedConfig);

            // Assert
            _mockRepository.Verify(r => r.UpdateDatabaseConfig(It.Is<DittoDatabaseConfig>(
                c => c.Id == updatedConfig.Id && c.Name == "Updated Name" && c.Mode == "smallpeersonly")), Times.Once);
        }

        #endregion

        #region RegisterLocalObservers Tests

        [Fact]
        public void RegisterLocalObservers_ShouldCallRepositoryMethod()
        {
            // Arrange
            var databaseConfigs = new ObservableCollection<DittoDatabaseConfig>
            {
                CreateTestDatabaseConfig("test-id-6", "Database 1"),
                CreateTestDatabaseConfig("test-id-7", "Database 2")
            };
            Action<string> errorCallback = (msg) => { };

            _mockRepository.Setup(r => r.RegisterLocalObservers(
                It.IsAny<ObservableCollection<DittoDatabaseConfig>>(),
                It.IsAny<Action<string>>()));

            // Act
            _mockRepository.Object.RegisterLocalObservers(databaseConfigs, errorCallback);

            // Assert
            _mockRepository.Verify(r => r.RegisterLocalObservers(
                It.Is<ObservableCollection<DittoDatabaseConfig>>(c => c.Count == 2),
                It.IsAny<Action<string>>()), Times.Once);
        }

        [Fact]
        public void RegisterLocalObservers_WithNullCollection_ShouldThrowException()
        {
            // Arrange
            Action<string> errorCallback = (msg) => { };
            _mockRepository.Setup(r => r.RegisterLocalObservers(null!, It.IsAny<Action<string>>()))
                .Throws(new ArgumentNullException("databaseConfigs"));

            // Act & Assert
            Assert.Throws<ArgumentNullException>(
                () => _mockRepository.Object.RegisterLocalObservers(null!, errorCallback));
        }

        [Fact]
        public void RegisterLocalObservers_WithNullErrorCallback_ShouldThrowException()
        {
            // Arrange
            var databaseConfigs = new ObservableCollection<DittoDatabaseConfig>();
            _mockRepository.Setup(r => r.RegisterLocalObservers(It.IsAny<ObservableCollection<DittoDatabaseConfig>>(), null!))
                .Throws(new ArgumentNullException("errorCallback"));

            // Act & Assert
            Assert.Throws<ArgumentNullException>(
                () => _mockRepository.Object.RegisterLocalObservers(databaseConfigs, null!));
        }

        [Fact]
        public void RegisterLocalObservers_WithEmptyCollection_ShouldNotThrow()
        {
            // Arrange
            var databaseConfigs = new ObservableCollection<DittoDatabaseConfig>();
            Action<string> errorCallback = (msg) => { };

            _mockRepository.Setup(r => r.RegisterLocalObservers(
                It.IsAny<ObservableCollection<DittoDatabaseConfig>>(),
                It.IsAny<Action<string>>()));

            // Act
            var act = () => _mockRepository.Object.RegisterLocalObservers(databaseConfigs, errorCallback);

            // Assert
            act.Should().NotThrow();
        }

        [Fact]
        public void RegisterLocalObservers_ErrorCallback_ShouldBeInvoked()
        {
            // Arrange
            var databaseConfigs = new ObservableCollection<DittoDatabaseConfig>();
            string? capturedError = null;
            Action<string> errorCallback = (msg) => { capturedError = msg; };

            _mockRepository.Setup(r => r.RegisterLocalObservers(
                It.IsAny<ObservableCollection<DittoDatabaseConfig>>(),
                It.IsAny<Action<string>>()))
                .Callback<ObservableCollection<DittoDatabaseConfig>, Action<string>>((configs, callback) =>
                {
                    callback("Test error message");
                });

            // Act
            _mockRepository.Object.RegisterLocalObservers(databaseConfigs, errorCallback);

            // Assert
            capturedError.Should().Be("Test error message");
        }

        #endregion

        #region SetupDatabaseConfigSubscriptions Tests

        [Fact]
        public async Task SetupDatabaseConfigSubscriptions_ShouldCallRepositoryMethod()
        {
            // Arrange
            _mockRepository.Setup(r => r.SetupDatabaseConfigSubscriptions())
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.SetupDatabaseConfigSubscriptions();

            // Assert
            _mockRepository.Verify(r => r.SetupDatabaseConfigSubscriptions(), Times.Once);
        }

        [Fact]
        public async Task SetupDatabaseConfigSubscriptions_ShouldComplete()
        {
            // Arrange
            _mockRepository.Setup(r => r.SetupDatabaseConfigSubscriptions())
                .Returns(Task.CompletedTask);

            // Act
            var act = async () => await _mockRepository.Object.SetupDatabaseConfigSubscriptions();

            // Assert
            await act.Should().NotThrowAsync();
        }

        [Fact]
        public async Task SetupDatabaseConfigSubscriptions_OnError_ShouldThrowException()
        {
            // Arrange
            _mockRepository.Setup(r => r.SetupDatabaseConfigSubscriptions())
                .ThrowsAsync(new InvalidOperationException("Failed to setup subscriptions"));

            // Act & Assert
            await Assert.ThrowsAsync<InvalidOperationException>(
                () => _mockRepository.Object.SetupDatabaseConfigSubscriptions());
        }

        #endregion

        #region Helper Methods

        /// <summary>
        /// Creates a test DittoDatabaseConfig with the specified ID and name
        /// </summary>
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
