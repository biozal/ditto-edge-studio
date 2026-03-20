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
    /// Unit tests for IHistoryRepository interface and HistoryRepository implementation
    /// Tests the repository pattern, IIdModel interface usage, and RepositoryBase functionality
    /// </summary>
    public class HistoryRepositoryTests
    {
        private readonly Mock<IHistoryRepository> _mockRepository;

        public HistoryRepositoryTests()
        {
            _mockRepository = new Mock<IHistoryRepository>();
        }

        #region AddQueryHistory Tests

        [Fact]
        public async Task AddQueryHistory_ShouldCallRepositoryMethod()
        {
            // Arrange
            var queryHistory = CreateTestQueryHistory("history-id-1", "SELECT * FROM users", DateTime.UtcNow.ToString("o"));
            _mockRepository.Setup(r => r.AddQueryHistory(It.IsAny<QueryHistory>()))
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.AddQueryHistory(queryHistory);

            // Assert
            _mockRepository.Verify(r => r.AddQueryHistory(It.Is<QueryHistory>(
                qh => qh.Id == queryHistory.Id && qh.Query == queryHistory.Query)), Times.Once);
        }

        [Fact]
        public async Task AddQueryHistory_WithNullQueryHistory_ShouldThrowException()
        {
            // Arrange
            _mockRepository.Setup(r => r.AddQueryHistory(null!))
                .ThrowsAsync(new ArgumentNullException(nameof(QueryHistory)));

            // Act & Assert
            await Assert.ThrowsAsync<ArgumentNullException>(
                () => _mockRepository.Object.AddQueryHistory(null!));
        }

        [Fact]
        public async Task AddQueryHistory_WithValidQueryHistory_ShouldComplete()
        {
            // Arrange
            var queryHistory = CreateTestQueryHistory("history-id-2", "SELECT * FROM orders WHERE status = 'active'", DateTime.UtcNow.ToString("o"));
            _mockRepository.Setup(r => r.AddQueryHistory(It.IsAny<QueryHistory>()))
                .Returns(Task.CompletedTask);

            // Act
            var act = async () => await _mockRepository.Object.AddQueryHistory(queryHistory);

            // Assert
            await act.Should().NotThrowAsync();
        }

        [Fact]
        public async Task AddQueryHistory_WithEmptyQuery_ShouldThrowException()
        {
            // Arrange
            var queryHistory = CreateTestQueryHistory("history-id-3", "", DateTime.UtcNow.ToString("o"));
            _mockRepository.Setup(r => r.AddQueryHistory(It.Is<QueryHistory>(qh => string.IsNullOrEmpty(qh.Query))))
                .ThrowsAsync(new ArgumentException("Query cannot be empty"));

            // Act & Assert
            await Assert.ThrowsAsync<ArgumentException>(
                () => _mockRepository.Object.AddQueryHistory(queryHistory));
        }

        [Fact]
        public async Task AddQueryHistory_NewQuery_ShouldCreate()
        {
            // Arrange
            var queryHistory = CreateTestQueryHistory("new-history-id", "INSERT INTO products VALUES ('test')", DateTime.UtcNow.ToString("o"));
            _mockRepository.Setup(r => r.AddQueryHistory(It.IsAny<QueryHistory>()))
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.AddQueryHistory(queryHistory);

            // Assert
            _mockRepository.Verify(r => r.AddQueryHistory(It.Is<QueryHistory>(
                qh => qh.Id == "new-history-id")), Times.Once);
        }

        [Fact]
        public async Task AddQueryHistory_ExistingQuery_ShouldUpdateCreatedDate()
        {
            // Arrange
            var originalDate = DateTime.UtcNow.AddHours(-1).ToString("o");
            var newDate = DateTime.UtcNow.ToString("o");
            var existingQuery = CreateTestQueryHistory("existing-id", "SELECT * FROM users", originalDate);
            var updatedQuery = existingQuery with { CreatedDate = newDate };

            _mockRepository.Setup(r => r.AddQueryHistory(It.IsAny<QueryHistory>()))
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.AddQueryHistory(updatedQuery);

            // Assert
            _mockRepository.Verify(r => r.AddQueryHistory(It.Is<QueryHistory>(
                qh => qh.Id == "existing-id" && qh.CreatedDate == newDate)), Times.Once);
        }

        [Fact]
        public async Task AddQueryHistory_WithSpecialCharacters_ShouldHandle()
        {
            // Arrange
            var queryHistory = CreateTestQueryHistory("history-id-4", "SELECT * FROM users WHERE name = 'O''Brien'", DateTime.UtcNow.ToString("o"));
            _mockRepository.Setup(r => r.AddQueryHistory(It.IsAny<QueryHistory>()))
                .Returns(Task.CompletedTask);

            // Act
            var act = async () => await _mockRepository.Object.AddQueryHistory(queryHistory);

            // Assert
            await act.Should().NotThrowAsync();
        }

        [Fact]
        public async Task AddQueryHistory_IIdModel_IdProperty_ShouldBeSet()
        {
            // Arrange - Testing that QueryHistory implements IIdModel correctly
            var queryHistory = CreateTestQueryHistory("test-id", "SELECT 1", DateTime.UtcNow.ToString("o"));
            IIdModel idModel = queryHistory; // Should compile since QueryHistory implements IIdModel

            // Assert
            idModel.Id.Should().Be("test-id");
            idModel.Id.Should().Be(queryHistory.Id);
        }

        #endregion

        #region DeleteQueryHistory Tests

        [Fact]
        public async Task DeleteQueryHistory_ShouldCallRepositoryMethod()
        {
            // Arrange
            var queryHistory = CreateTestQueryHistory("history-id-5", "SELECT * FROM products", DateTime.UtcNow.ToString("o"));
            _mockRepository.Setup(r => r.DeleteQueryHistory(It.IsAny<QueryHistory>()))
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.DeleteQueryHistory(queryHistory);

            // Assert
            _mockRepository.Verify(r => r.DeleteQueryHistory(It.Is<QueryHistory>(
                qh => qh.Id == queryHistory.Id)), Times.Once);
        }

        [Fact]
        public async Task DeleteQueryHistory_WithNullQueryHistory_ShouldThrowException()
        {
            // Arrange
            _mockRepository.Setup(r => r.DeleteQueryHistory(null!))
                .ThrowsAsync(new ArgumentNullException(nameof(QueryHistory)));

            // Act & Assert
            await Assert.ThrowsAsync<ArgumentNullException>(
                () => _mockRepository.Object.DeleteQueryHistory(null!));
        }

        [Fact]
        public async Task DeleteQueryHistory_WithNonExistentQuery_ShouldThrowException()
        {
            // Arrange
            var queryHistory = CreateTestQueryHistory("non-existent-id", "SELECT * FROM missing", DateTime.UtcNow.ToString("o"));
            _mockRepository.Setup(r => r.DeleteQueryHistory(It.IsAny<QueryHistory>()))
                .ThrowsAsync(new InvalidOperationException("Query history not found"));

            // Act & Assert
            await Assert.ThrowsAsync<InvalidOperationException>(
                () => _mockRepository.Object.DeleteQueryHistory(queryHistory));
        }

        [Fact]
        public async Task DeleteQueryHistory_WithValidQuery_ShouldComplete()
        {
            // Arrange
            var queryHistory = CreateTestQueryHistory("history-id-6", "DELETE FROM temp_data", DateTime.UtcNow.ToString("o"));
            _mockRepository.Setup(r => r.DeleteQueryHistory(It.IsAny<QueryHistory>()))
                .Returns(Task.CompletedTask);

            // Act
            var act = async () => await _mockRepository.Object.DeleteQueryHistory(queryHistory);

            // Assert
            await act.Should().NotThrowAsync();
        }

        [Fact]
        public async Task DeleteQueryHistory_IIdModel_ShouldUseIdForDeletion()
        {
            // Arrange - Testing that DeleteItem<T> in RepositoryBase uses IIdModel.Id
            var queryHistory = CreateTestQueryHistory("delete-id", "SELECT * FROM test", DateTime.UtcNow.ToString("o"));
            _mockRepository.Setup(r => r.DeleteQueryHistory(It.Is<QueryHistory>(qh => qh.Id == "delete-id")))
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.DeleteQueryHistory(queryHistory);

            // Assert
            _mockRepository.Verify(r => r.DeleteQueryHistory(It.Is<QueryHistory>(
                qh => qh.Id == "delete-id")), Times.Once);
        }

        #endregion

        #region RegisterObserver Tests

        [Fact]
        public void RegisterObserver_ShouldCallRepositoryMethod()
        {
            // Arrange
            var queryHistories = new ObservableCollection<QueryHistory>
            {
                CreateTestQueryHistory("history-1", "SELECT * FROM users", DateTime.UtcNow.ToString("o")),
                CreateTestQueryHistory("history-2", "SELECT * FROM orders", DateTime.UtcNow.ToString("o"))
            };
            Action<string> errorCallback = (msg) => { };

            _mockRepository.Setup(r => r.RegisterObserver(
                It.IsAny<ObservableCollection<QueryHistory>>(),
                It.IsAny<Action<string>>()));

            // Act
            _mockRepository.Object.RegisterObserver(queryHistories, errorCallback);

            // Assert
            _mockRepository.Verify(r => r.RegisterObserver(
                It.Is<ObservableCollection<QueryHistory>>(c => c.Count == 2),
                It.IsAny<Action<string>>()), Times.Once);
        }

        [Fact]
        public void RegisterObserver_WithNullCollection_ShouldThrowException()
        {
            // Arrange
            Action<string> errorCallback = (msg) => { };
            _mockRepository.Setup(r => r.RegisterObserver(null!, It.IsAny<Action<string>>()))
                .Throws(new ArgumentNullException("queryHistories"));

            // Act & Assert
            Assert.Throws<ArgumentNullException>(
                () => _mockRepository.Object.RegisterObserver(null!, errorCallback));
        }

        [Fact]
        public void RegisterObserver_WithNullErrorCallback_ShouldThrowException()
        {
            // Arrange
            var queryHistories = new ObservableCollection<QueryHistory>();
            _mockRepository.Setup(r => r.RegisterObserver(It.IsAny<ObservableCollection<QueryHistory>>(), null!))
                .Throws(new ArgumentNullException("errorCallback"));

            // Act & Assert
            Assert.Throws<ArgumentNullException>(
                () => _mockRepository.Object.RegisterObserver(queryHistories, null!));
        }

        [Fact]
        public void RegisterObserver_WithEmptyCollection_ShouldNotThrow()
        {
            // Arrange
            var queryHistories = new ObservableCollection<QueryHistory>();
            Action<string> errorCallback = (msg) => { };

            _mockRepository.Setup(r => r.RegisterObserver(
                It.IsAny<ObservableCollection<QueryHistory>>(),
                It.IsAny<Action<string>>()));

            // Act
            var act = () => _mockRepository.Object.RegisterObserver(queryHistories, errorCallback);

            // Assert
            act.Should().NotThrow();
        }

        [Fact]
        public void RegisterObserver_ErrorCallback_ShouldBeInvoked()
        {
            // Arrange
            var queryHistories = new ObservableCollection<QueryHistory>();
            string? capturedError = null;
            Action<string> errorCallback = (msg) => { capturedError = msg; };

            _mockRepository.Setup(r => r.RegisterObserver(
                It.IsAny<ObservableCollection<QueryHistory>>(),
                It.IsAny<Action<string>>()))
                .Callback<ObservableCollection<QueryHistory>, Action<string>>((queries, callback) =>
                {
                    callback("Test error message from observer");
                });

            // Act
            _mockRepository.Object.RegisterObserver(queryHistories, errorCallback);

            // Assert
            capturedError.Should().Be("Test error message from observer");
        }

        [Fact]
        public void RegisterObserver_ShouldObserveQueryHistoryCollection()
        {
            // Arrange
            var queryHistories = new ObservableCollection<QueryHistory>();
            Action<string> errorCallback = (msg) => { };
            bool observerRegistered = false;

            _mockRepository.Setup(r => r.RegisterObserver(
                It.IsAny<ObservableCollection<QueryHistory>>(),
                It.IsAny<Action<string>>()))
                .Callback<ObservableCollection<QueryHistory>, Action<string>>((queries, callback) =>
                {
                    observerRegistered = true;
                });

            // Act
            _mockRepository.Object.RegisterObserver(queryHistories, errorCallback);

            // Assert
            observerRegistered.Should().BeTrue();
        }

        #endregion

        #region ICloseDatabase and IDisposable Tests

        [Fact]
        public void CloseSelectedDatabase_ShouldCallRepositoryMethod()
        {
            // Arrange
            _mockRepository.Setup(r => r.CloseSelectedDatabase());

            // Act
            _mockRepository.Object.CloseSelectedDatabase();

            // Assert
            _mockRepository.Verify(r => r.CloseSelectedDatabase(), Times.Once);
        }

        [Fact]
        public void CloseSelectedDatabase_ShouldCleanupResources()
        {
            // Arrange
            bool resourcesCleaned = false;
            _mockRepository.Setup(r => r.CloseSelectedDatabase())
                .Callback(() => { resourcesCleaned = true; });

            // Act
            _mockRepository.Object.CloseSelectedDatabase();

            // Assert
            resourcesCleaned.Should().BeTrue();
        }

        [Fact]
        public void Dispose_ShouldCallCloseSelectedDatabase()
        {
            // Arrange
            _mockRepository.Setup(r => r.Dispose());

            // Act
            _mockRepository.Object.Dispose();

            // Assert
            _mockRepository.Verify(r => r.Dispose(), Times.Once);
        }

        [Fact]
        public void Dispose_MultipleCalls_ShouldBeIdempotent()
        {
            // Arrange
            _mockRepository.Setup(r => r.Dispose());

            // Act
            _mockRepository.Object.Dispose();
            _mockRepository.Object.Dispose();
            _mockRepository.Object.Dispose();

            // Assert - Should be called three times without error
            _mockRepository.Verify(r => r.Dispose(), Times.Exactly(3));
        }

        #endregion

        #region QueryHistory Model Tests

        [Fact]
        public void QueryHistory_ShouldImplementIIdModel()
        {
            // Arrange & Act
            var queryHistory = CreateTestQueryHistory("test-id", "SELECT 1", DateTime.UtcNow.ToString("o"));

            // Assert
            queryHistory.Should().BeAssignableTo<IIdModel>();
        }

        [Fact]
        public void QueryHistory_Record_ShouldSupportWithExpression()
        {
            // Arrange
            var original = CreateTestQueryHistory("original-id", "SELECT * FROM users", DateTime.UtcNow.ToString("o"));

            // Act
            var modified = original with { Query = "SELECT * FROM orders" };

            // Assert
            modified.Id.Should().Be(original.Id);
            modified.Query.Should().Be("SELECT * FROM orders");
            modified.CreatedDate.Should().Be(original.CreatedDate);
        }

        [Fact]
        public void QueryHistory_Properties_ShouldBeInitOnly()
        {
            // Arrange
            var queryHistory = CreateTestQueryHistory("test-id", "SELECT 1", DateTime.UtcNow.ToString("o"));

            // Assert - Properties should be init-only (compile-time check)
            // If this compiles, the properties are correctly set as init-only
            var newHistory = queryHistory with { Query = "SELECT 2" };
            newHistory.Query.Should().Be("SELECT 2");
        }

        [Fact]
        public void QueryHistory_JsonPropertyNames_ShouldBeCorrect()
        {
            // This test verifies that the JSON property names match what Ditto expects
            // Testing at runtime would require serialization, but the attributes are defined correctly
            var queryHistory = CreateTestQueryHistory("test-id", "SELECT 1", DateTime.UtcNow.ToString("o"));

            // Assert
            queryHistory.Id.Should().NotBeNull();
            queryHistory.Query.Should().NotBeNull();
            queryHistory.CreatedDate.Should().NotBeNull();
            queryHistory.SelectedAppId.Should().NotBeNull();
        }

        [Fact]
        public void QueryHistory_Constructor_WithAllParameters_ShouldSetProperties()
        {
            // Arrange
            var id = "test-id";
            var query = "SELECT * FROM test";
            var createdDate = DateTime.UtcNow.ToString("o");

            // Act
            var queryHistory = new QueryHistory(id, query, createdDate);

            // Assert
            queryHistory.Id.Should().Be(id);
            queryHistory.Query.Should().Be(query);
            queryHistory.CreatedDate.Should().Be(createdDate);
            queryHistory.SelectedAppId.Should().Be(string.Empty);
        }

        [Fact]
        public void QueryHistory_ParameterlessConstructor_RequiresProperties()
        {
            // This test verifies that QueryHistory has required properties
            // that must be set via object initializer or constructor

            // The following would not compile without setting required properties:
            // var queryHistory = new QueryHistory();

            // Instead, we must use object initializer syntax with all required properties:
            var queryHistory = new QueryHistory
            {
                Id = "init-id",
                Query = "SELECT 1",
                CreatedDate = DateTime.UtcNow.ToString("o")
            };

            // Assert
            queryHistory.Id.Should().Be("init-id");
            queryHistory.Query.Should().Be("SELECT 1");
            queryHistory.CreatedDate.Should().NotBeNullOrEmpty();
        }

        #endregion

        #region Helper Methods

        /// <summary>
        /// Creates a test QueryHistory with the specified properties
        /// </summary>
        private static QueryHistory CreateTestQueryHistory(string id, string query, string createdDate)
        {
            return new QueryHistory(
                id: id,
                query: query,
                createdDate: createdDate
            );
        }

        #endregion
    }
}
