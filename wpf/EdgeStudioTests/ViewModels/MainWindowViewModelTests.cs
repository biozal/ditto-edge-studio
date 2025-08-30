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
        private Mock<IDittoManager> _mockDittoManager = null!;
        private Mock<IDatabaseRepository> _mockDatabaseRepository = null!;
        private MainWindowViewModel _viewModel = null!;

        [TestInitialize]
        public void Setup()
        {
            _mockDittoManager = new Mock<IDittoManager>();
            _mockDatabaseRepository = new Mock<IDatabaseRepository>();
            
            // Setup the async methods that are called during initialization
            _mockDatabaseRepository.Setup(x => x.SetupDatabaseConfigSubscriptions())
                .Returns(Task.CompletedTask);
            _mockDatabaseRepository.Setup(x => x.RegisterLocalObservers(It.IsAny<ObservableCollection<DittoDatabaseConfig>>(), It.IsAny<Action<string>>()));
            
            _viewModel = new MainWindowViewModel(_mockDittoManager.Object, _mockDatabaseRepository.Object);
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
            Assert.AreEqual("SELECT * FROM collection", _viewModel.QueryText);
            Assert.AreEqual("Query results will appear here...", _viewModel.QueryResults);
            Assert.IsFalse(_viewModel.IsLoading);
            Assert.IsNull(_viewModel.SelectedDatabaseConfig);
        }

        [TestMethod]
        public void Constructor_WithNullDittoManager_ThrowsArgumentNullException()
        {
            // Act & Assert
            Assert.ThrowsException<ArgumentNullException>(() =>
                new MainWindowViewModel(null!, _mockDatabaseRepository.Object));
        }

        [TestMethod]
        public void Constructor_WithNullDatabaseRepository_ThrowsArgumentNullException()
        {
            // Act & Assert
            Assert.ThrowsException<ArgumentNullException>(() =>
                new MainWindowViewModel(_mockDittoManager.Object, null!));
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
        public async Task ExecuteQueryCommand_WithValidQuery_ExecutesSuccessfully()
        {
            // Arrange
            var initialQueryText = "SELECT * FROM test";
            _viewModel.QueryText = initialQueryText;
            
            // Act
            await _viewModel.ExecuteQueryCommand.ExecuteAsync(null);
            
            // Assert
            Assert.IsFalse(_viewModel.IsLoading);
            Assert.IsTrue(_viewModel.QueryResults.Contains("Query executed"));
            Assert.IsTrue(_viewModel.QueryResults.Contains(initialQueryText));
        }

        [TestMethod]
        public async Task ExecuteQueryCommand_WithEmptyQuery_DoesNotExecute()
        {
            // Arrange
            _viewModel.QueryText = "";
            var originalResults = _viewModel.QueryResults;
            
            // Act
            await _viewModel.ExecuteQueryCommand.ExecuteAsync(null);
            
            // Assert
            Assert.AreEqual(originalResults, _viewModel.QueryResults);
            Assert.IsFalse(_viewModel.IsLoading);
        }

        [TestMethod]
        public void ClearQueryCommand_ClearsTextAndResults()
        {
            // Arrange
            _viewModel.QueryText = "SELECT * FROM test";
            _viewModel.QueryResults = "Some results";
            
            // Act
            _viewModel.ClearQueryCommand.Execute(null);
            
            // Assert
            Assert.AreEqual(string.Empty, _viewModel.QueryText);
            Assert.AreEqual("Query results will appear here...", _viewModel.QueryResults);
        }

        [TestMethod]
        public void AddDatabaseCommand_TriggersShowAddDatabaseForm()
        {
            // Arrange
            bool eventTriggered = false;
            _viewModel.ShowAddDatabaseForm += () => eventTriggered = true;
            
            // Act
            _viewModel.AddDatabaseCommand.Execute(null);
            
            // Assert
            Assert.IsTrue(eventTriggered);
            Assert.IsFalse(_viewModel.DatabaseFormModel.IsEditMode);
            Assert.AreEqual(string.Empty, _viewModel.DatabaseFormModel.Name);
        }

        [TestMethod]
        public void EditDatabaseCommand_WithValidConfig_TriggersShowEditDatabaseForm()
        {
            // Arrange
            var config = CreateTestDatabaseConfig();
            bool eventTriggered = false;
            _viewModel.ShowEditDatabaseForm += () => eventTriggered = true;
            
            // Act
            _viewModel.EditDatabaseCommand.Execute(config);
            
            // Assert
            Assert.IsTrue(eventTriggered);
            Assert.IsTrue(_viewModel.DatabaseFormModel.IsEditMode);
            Assert.AreEqual(config.Name, _viewModel.DatabaseFormModel.Name);
            Assert.AreEqual(config.DatabaseId, _viewModel.DatabaseFormModel.DatabaseId);
        }

        [TestMethod]
        public async Task DeleteDatabaseCommand_WithValidConfig_CallsRepositoryDelete()
        {
            // Arrange
            var config = CreateTestDatabaseConfig();
            
            // Act
            await _viewModel.DeleteDatabaseCommand.ExecuteAsync(config);
            
            // Assert
            _mockDatabaseRepository.Verify(r => r.DeleteDittoDatabaseConfig(config), Times.Once);
        }

        [TestMethod]
        public async Task DeleteDatabaseCommand_WithNullConfig_TriggersErrorEvent()
        {
            // Arrange
            string? errorMessage = null;
            _viewModel.ErrorOccurred += (sender, message) => errorMessage = message;
            
            // Act
            await _viewModel.DeleteDatabaseCommand.ExecuteAsync(null);
            
            // Assert
            Assert.IsNotNull(errorMessage);
            Assert.IsTrue(errorMessage.Contains("null"));
            _mockDatabaseRepository.Verify(r => r.DeleteDittoDatabaseConfig(It.IsAny<DittoDatabaseConfig>()), Times.Never);
        }

        [TestMethod]
        public async Task DeleteDatabaseCommand_WhenRepositoryThrows_TriggersErrorEvent()
        {
            // Arrange
            var config = CreateTestDatabaseConfig();
            var expectedException = new InvalidOperationException("Database error");
            _mockDatabaseRepository.Setup(r => r.DeleteDittoDatabaseConfig(config))
                                 .ThrowsAsync(expectedException);
            
            string? errorMessage = null;
            _viewModel.ErrorOccurred += (sender, message) => errorMessage = message;
            
            // Act
            await _viewModel.DeleteDatabaseCommand.ExecuteAsync(config);
            
            // Assert
            Assert.IsNotNull(errorMessage);
            Assert.IsTrue(errorMessage.Contains("Failed to delete database configuration"));
            Assert.IsTrue(errorMessage.Contains("Database error"));
        }

        [TestMethod]
        public async Task SaveDatabaseCommand_WithValidData_CallsRepositoryAdd()
        {
            // Arrange
            _viewModel.DatabaseFormModel.Name = "Test DB";
            _viewModel.DatabaseFormModel.DatabaseId = "test-id";
            _viewModel.DatabaseFormModel.AuthToken = "test-token";
            _viewModel.DatabaseFormModel.AuthUrl = "https://test.com";
            _viewModel.DatabaseFormModel.IsEditMode = false;
            
            // Act
            await _viewModel.SaveDatabaseCommand.ExecuteAsync(null);
            
            // Assert
            _mockDatabaseRepository.Verify(r => r.AddDittoDatabaseConfig(It.IsAny<DittoDatabaseConfig>()), Times.Once);
        }

        [TestMethod]
        public async Task SaveDatabaseCommand_WithValidDataInEditMode_CallsRepositoryUpdate()
        {
            // Arrange
            _viewModel.DatabaseFormModel.Name = "Test DB";
            _viewModel.DatabaseFormModel.DatabaseId = "test-id";
            _viewModel.DatabaseFormModel.AuthToken = "test-token";
            _viewModel.DatabaseFormModel.AuthUrl = "https://test.com";
            _viewModel.DatabaseFormModel.IsEditMode = true;
            
            // Act
            await _viewModel.SaveDatabaseCommand.ExecuteAsync(null);
            
            // Assert
            _mockDatabaseRepository.Verify(r => r.UpdateDatabaseConfig(It.IsAny<DittoDatabaseConfig>()), Times.Once);
        }

        [TestMethod]
        public async Task SaveDatabaseCommand_WithMissingName_TriggersValidationError()
        {
            // Arrange
            _viewModel.DatabaseFormModel.Name = ""; // Missing required field
            _viewModel.DatabaseFormModel.DatabaseId = "test-id";
            _viewModel.DatabaseFormModel.AuthToken = "test-token";
            _viewModel.DatabaseFormModel.AuthUrl = "https://test.com";
            
            string? errorMessage = null;
            _viewModel.ErrorOccurred += (sender, message) => errorMessage = message;
            
            // Act
            await _viewModel.SaveDatabaseCommand.ExecuteAsync(null);
            
            // Assert
            Assert.IsNotNull(errorMessage);
            Assert.IsTrue(errorMessage.Contains("required fields"));
            _mockDatabaseRepository.Verify(r => r.AddDittoDatabaseConfig(It.IsAny<DittoDatabaseConfig>()), Times.Never);
            _mockDatabaseRepository.Verify(r => r.UpdateDatabaseConfig(It.IsAny<DittoDatabaseConfig>()), Times.Never);
        }

        [TestMethod]
        public async Task SaveDatabaseCommand_WithMissingDatabaseId_TriggersValidationError()
        {
            // Arrange
            _viewModel.DatabaseFormModel.Name = "Test DB";
            _viewModel.DatabaseFormModel.DatabaseId = ""; // Missing required field
            _viewModel.DatabaseFormModel.AuthToken = "test-token";
            _viewModel.DatabaseFormModel.AuthUrl = "https://test.com";
            
            string? errorMessage = null;
            _viewModel.ErrorOccurred += (sender, message) => errorMessage = message;
            
            // Act
            await _viewModel.SaveDatabaseCommand.ExecuteAsync(null);
            
            // Assert
            Assert.IsNotNull(errorMessage);
            Assert.IsTrue(errorMessage.Contains("required fields"));
        }

        [TestMethod]
        public async Task SaveDatabaseCommand_WhenRepositoryThrows_TriggersErrorEvent()
        {
            // Arrange
            _viewModel.DatabaseFormModel.Name = "Test DB";
            _viewModel.DatabaseFormModel.DatabaseId = "test-id";
            _viewModel.DatabaseFormModel.AuthToken = "test-token";
            _viewModel.DatabaseFormModel.AuthUrl = "https://test.com";
            
            var expectedException = new InvalidOperationException("Save failed");
            _mockDatabaseRepository.Setup(r => r.AddDittoDatabaseConfig(It.IsAny<DittoDatabaseConfig>()))
                                 .ThrowsAsync(expectedException);
            
            string? errorMessage = null;
            _viewModel.ErrorOccurred += (sender, message) => errorMessage = message;
            
            // Act
            await _viewModel.SaveDatabaseCommand.ExecuteAsync(null);
            
            // Assert
            Assert.IsNotNull(errorMessage);
            Assert.IsTrue(errorMessage.Contains("Failed to save database configuration"));
        }

        [TestMethod]
        public void CancelDatabaseForm_ResetsFormModel()
        {
            // Arrange
            _viewModel.DatabaseFormModel.Name = "Test";
            _viewModel.DatabaseFormModel.IsEditMode = true;
            
            // Act
            _viewModel.CancelDatabaseForm();
            
            // Assert
            Assert.AreEqual(string.Empty, _viewModel.DatabaseFormModel.Name);
            Assert.IsFalse(_viewModel.DatabaseFormModel.IsEditMode);
        }

        [TestMethod]
        public void DatabaseConfigs_CollectionChanged_UpdatesHasDatabaseConfigs()
        {
            // Arrange
            var initialHasConfigs = _viewModel.HasDatabaseConfigs;
            
            // Act
            _viewModel.DatabaseConfigs.Add(CreateTestDatabaseConfig());
            
            // Assert
            Assert.AreNotEqual(initialHasConfigs, _viewModel.HasDatabaseConfigs);
        }

        private static DittoDatabaseConfig CreateTestDatabaseConfig()
        {
            return new DittoDatabaseConfig(
                Id: Guid.NewGuid().ToString(),
                Name: "Test Database",
                DatabaseId: "test-db-id",
                AuthToken: "test-token",
                AuthUrl: "https://test.example.com",
                HttpApiUrl: "https://api.test.example.com",
                HttpApiKey: "test-api-key",
                Mode: "default",
                AllowUntrustedCerts: false
            );
        }
    }
}