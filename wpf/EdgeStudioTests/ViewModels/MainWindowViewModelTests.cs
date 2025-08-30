using EdgeStudio.Data;
using EdgeStudio.Data.Repositories;
using EdgeStudio.Models;
using EdgeStudio.ViewModels;
using Moq;
using System.Collections.ObjectModel;

namespace EdgeStudioTests.ViewModels
{
    [TestClass]
    public class MainWindowViewModelTests
    {
        private Mock<IDatabaseRepository> _mockDatabaseRepository = null!;
        private MainWindowViewModel _viewModel = null!;

        [TestInitialize]
        public void Setup()
        {
            _mockDatabaseRepository = new Mock<IDatabaseRepository>();
            
            // Setup the async methods that are called during initialization
            _mockDatabaseRepository.Setup(x => x.SetupDatabaseConfigSubscriptions())
                .Returns(Task.CompletedTask);
            _mockDatabaseRepository.Setup(x => x.RegisterLocalObservers(It.IsAny<ObservableCollection<DittoDatabaseConfig>>(), It.IsAny<Action<string>>()));
            
            _viewModel = new MainWindowViewModel(_mockDatabaseRepository.Object);
        }

        [TestCleanup]
        public void Cleanup()
        {
            _viewModel.Cleanup();
        }

        [TestMethod]
        public void Constructor_InitializesProperties()
        {
            // Assert
            Assert.IsNotNull(_viewModel.DatabaseConfigs);
            Assert.IsNotNull(_viewModel.DatabaseFormModel);
            Assert.IsFalse(_viewModel.IsLoading);
            Assert.IsNull(_viewModel.SelectedDatabaseConfig);
        }

        [TestMethod]
        public void Constructor_WithNullDatabaseRepository_ThrowsArgumentNullException()
        {
            // Act & Assert
            Assert.ThrowsException<ArgumentNullException>(() =>
                new MainWindowViewModel(null!));
        }

        [TestMethod]
        public void HasDatabaseConfigs_WhenCollectionIsEmpty_ReturnsTrue()
        {
            // Arrange - collection is empty by default
            
            // Act & Assert
            Assert.IsTrue(_viewModel.HasDatabaseConfigs);
        }

        [TestMethod]
        public void HasDatabaseConfigs_WhenCollectionHasItems_ReturnsFalse()
        {
            // Arrange
            var config = CreateTestDatabaseConfig();
            _viewModel.DatabaseConfigs.Add(config);
            
            // Act & Assert
            Assert.IsFalse(_viewModel.HasDatabaseConfigs);
        }

        [TestMethod]
        public void AddDatabaseCommand_TriggersShowAddDatabaseForm()
        {
            // Arrange
            bool eventRaised = false;
            _viewModel.ShowAddDatabaseForm += () => eventRaised = true;
            
            // Act
            _viewModel.AddDatabaseCommand.Execute(null);
            
            // Assert
            Assert.IsTrue(eventRaised);
            Assert.IsFalse(_viewModel.DatabaseFormModel.IsEditMode);
        }

        [TestMethod]
        public void EditDatabaseCommand_WithValidConfig_TriggersShowEditDatabaseForm()
        {
            // Arrange
            bool eventRaised = false;
            _viewModel.ShowEditDatabaseForm += () => eventRaised = true;
            var config = CreateTestDatabaseConfig();
            
            // Act
            _viewModel.EditDatabaseCommand.Execute(config);
            
            // Assert
            Assert.IsTrue(eventRaised);
            Assert.IsTrue(_viewModel.DatabaseFormModel.IsEditMode);
            Assert.AreEqual(config.Name, _viewModel.DatabaseFormModel.Name);
        }

        [TestMethod]
        public void EditDatabaseCommand_WithNullConfig_DoesNotTriggerEvent()
        {
            // Arrange
            bool eventRaised = false;
            _viewModel.ShowEditDatabaseForm += () => eventRaised = true;
            
            // Act
            _viewModel.EditDatabaseCommand.Execute(null);
            
            // Assert
            Assert.IsFalse(eventRaised);
        }

        [TestMethod]
        public async Task SaveDatabaseCommand_ForNewDatabase_CallsAdd()
        {
            // Arrange
            _viewModel.DatabaseFormModel.Reset();
            _viewModel.DatabaseFormModel.Name = "Test Database";
            _viewModel.DatabaseFormModel.DatabaseId = "test-id";
            _viewModel.DatabaseFormModel.AuthToken = "test-token";
            _viewModel.DatabaseFormModel.AuthUrl = "https://auth.test.com";
            _viewModel.DatabaseFormModel.IsEditMode = false;
            
            _mockDatabaseRepository.Setup(x => x.AddDittoDatabaseConfig(It.IsAny<DittoDatabaseConfig>()))
                .Returns(Task.CompletedTask);
            
            // Act
            await _viewModel.SaveDatabaseCommand.ExecuteAsync(null);
            
            // Assert
            _mockDatabaseRepository.Verify(x => x.AddDittoDatabaseConfig(It.IsAny<DittoDatabaseConfig>()), Times.Once);
        }

        [TestMethod]
        public async Task SaveDatabaseCommand_ForExistingDatabase_CallsUpdate()
        {
            // Arrange
            var existingConfig = CreateTestDatabaseConfig();
            _viewModel.DatabaseFormModel.LoadFromConfig(existingConfig);
            _viewModel.DatabaseFormModel.Name = "Updated Name";
            
            _mockDatabaseRepository.Setup(x => x.UpdateDatabaseConfig(It.IsAny<DittoDatabaseConfig>()))
                .Returns(Task.CompletedTask);
            
            // Act
            await _viewModel.SaveDatabaseCommand.ExecuteAsync(null);
            
            // Assert
            _mockDatabaseRepository.Verify(x => x.UpdateDatabaseConfig(It.IsAny<DittoDatabaseConfig>()), Times.Once);
        }

        [TestMethod]
        public async Task SaveDatabaseCommand_WithError_RaisesErrorEvent()
        {
            // Arrange
            _viewModel.DatabaseFormModel.Reset();
            _viewModel.DatabaseFormModel.Name = "Test Database";
            _viewModel.DatabaseFormModel.DatabaseId = "test-id";
            _viewModel.DatabaseFormModel.AuthToken = "test-token";
            _viewModel.DatabaseFormModel.AuthUrl = "https://auth.test.com";
            
            string? errorMessage = null;
            _viewModel.ErrorOccurred += (sender, msg) => errorMessage = msg;
            
            _mockDatabaseRepository.Setup(x => x.AddDittoDatabaseConfig(It.IsAny<DittoDatabaseConfig>()))
                .ThrowsAsync(new Exception("Test error"));
            
            // Act
            await _viewModel.SaveDatabaseCommand.ExecuteAsync(null);
            
            // Assert
            Assert.IsNotNull(errorMessage);
            Assert.IsTrue(errorMessage.Contains("Test error"));
        }

        [TestMethod]
        public async Task DeleteDatabaseCommand_WithValidConfig_CallsDelete()
        {
            // Arrange
            var config = CreateTestDatabaseConfig();
            _mockDatabaseRepository.Setup(x => x.DeleteDittoDatabaseConfig(config))
                .Returns(Task.CompletedTask);
            
            // Act
            await _viewModel.DeleteDatabaseCommand.ExecuteAsync(config);
            
            // Assert
            _mockDatabaseRepository.Verify(x => x.DeleteDittoDatabaseConfig(config), Times.Once);
        }

        [TestMethod]
        public async Task DeleteDatabaseCommand_WithNullConfig_DoesNotCallDelete()
        {
            // Act
            await _viewModel.DeleteDatabaseCommand.ExecuteAsync(null);
            
            // Assert
            _mockDatabaseRepository.Verify(x => x.DeleteDittoDatabaseConfig(It.IsAny<DittoDatabaseConfig>()), Times.Never);
        }

        [TestMethod]
        public async Task DeleteDatabaseCommand_WithError_RaisesErrorEvent()
        {
            // Arrange
            var config = CreateTestDatabaseConfig();
            string? errorMessage = null;
            _viewModel.ErrorOccurred += (sender, msg) => errorMessage = msg;
            
            _mockDatabaseRepository.Setup(x => x.DeleteDittoDatabaseConfig(config))
                .ThrowsAsync(new Exception("Delete error"));
            
            // Act
            await _viewModel.DeleteDatabaseCommand.ExecuteAsync(config);
            
            // Assert
            Assert.IsNotNull(errorMessage);
            Assert.IsTrue(errorMessage.Contains("Delete error"));
        }

        [TestMethod]
        public void CancelDatabaseForm_ResetsFormModel()
        {
            // Arrange
            _viewModel.DatabaseFormModel.Name = "Test";
            _viewModel.DatabaseFormModel.DatabaseId = "test-id";
            
            // Act
            _viewModel.CancelDatabaseForm();
            
            // Assert
            Assert.AreEqual(string.Empty, _viewModel.DatabaseFormModel.Name);
            Assert.AreEqual(string.Empty, _viewModel.DatabaseFormModel.DatabaseId);
        }

        [TestMethod]
        public void PropertyChanged_WhenPropertyChanges_RaisesNotification()
        {
            // Arrange
            var propertyChangedEvents = new List<string>();
            _viewModel.PropertyChanged += (sender, e) =>
            {
                if (e.PropertyName != null)
                    propertyChangedEvents.Add(e.PropertyName);
            };

            // Act
            _viewModel.IsLoading = true;
            _viewModel.SelectedDatabaseConfig = CreateTestDatabaseConfig();

            // Assert
            Assert.IsTrue(propertyChangedEvents.Contains(nameof(_viewModel.IsLoading)));
            Assert.IsTrue(propertyChangedEvents.Contains(nameof(_viewModel.SelectedDatabaseConfig)));
        }

        // Note: Cleanup test removed as RemoveLocalObservers method is not defined in IDatabaseRepository

        private static DittoDatabaseConfig CreateTestDatabaseConfig()
        {
            return new DittoDatabaseConfig(
                Id: Guid.NewGuid().ToString(),
                Name: "Test Database",
                DatabaseId: "test-db-id",
                AuthToken: "test-token",
                AuthUrl: "https://auth.test.example.com",
                WebsocketUrl: "wss://ws.test.example.com",
                HttpApiUrl: "https://api.test.example.com",
                HttpApiKey: "test-api-key",
                Mode: "online",
                AllowUntrustedCerts: true
            );
        }
    }
}