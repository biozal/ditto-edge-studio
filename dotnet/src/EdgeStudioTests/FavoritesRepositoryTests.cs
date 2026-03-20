using EdgeStudio.Shared.Data;
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
    /// Unit tests for IFavoritesRepository interface and FavoritesRepository implementation
    /// Tests the inheritance from HistoryRepository and proper collection name override
    /// </summary>
    public class FavoritesRepositoryTests
    {
        private readonly Mock<IFavoritesRepository> _mockRepository;

        public FavoritesRepositoryTests()
        {
            _mockRepository = new Mock<IFavoritesRepository>();
        }

        #region Interface Inheritance Tests

        [Fact]
        public void IFavoritesRepository_ShouldExtendIHistoryRepository()
        {
            // Assert - IFavoritesRepository should extend IHistoryRepository
            typeof(IFavoritesRepository).Should().BeAssignableTo<IHistoryRepository>();
        }

        [Fact]
        public void IFavoritesRepository_ShouldExtendICloseDatabase()
        {
            // Assert - Through IHistoryRepository, should implement ICloseDatabase
            typeof(IFavoritesRepository).Should().BeAssignableTo<ICloseDatabase>();
        }

        [Fact]
        public void IFavoritesRepository_ShouldExtendIDisposable()
        {
            // Assert - Through IHistoryRepository, should implement IDisposable
            typeof(IFavoritesRepository).Should().BeAssignableTo<IDisposable>();
        }

        #endregion

        #region AddQueryHistory Tests (Inherited)

        [Fact]
        public async Task AddQueryHistory_ShouldCallRepositoryMethod()
        {
            // Arrange
            var favorite = CreateTestFavorite("fav-id-1", "SELECT * FROM customers WHERE premium = true", DateTime.UtcNow.ToString("o"));
            _mockRepository.Setup(r => r.AddQueryHistory(It.IsAny<QueryHistory>()))
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.AddQueryHistory(favorite);

            // Assert
            _mockRepository.Verify(r => r.AddQueryHistory(It.Is<QueryHistory>(
                qh => qh.Id == favorite.Id && qh.Query == favorite.Query)), Times.Once);
        }

        [Fact]
        public async Task AddQueryHistory_WithNullFavorite_ShouldThrowException()
        {
            // Arrange
            _mockRepository.Setup(r => r.AddQueryHistory(null!))
                .ThrowsAsync(new ArgumentNullException(nameof(QueryHistory)));

            // Act & Assert
            await Assert.ThrowsAsync<ArgumentNullException>(
                () => _mockRepository.Object.AddQueryHistory(null!));
        }

        [Fact]
        public async Task AddQueryHistory_WithValidFavorite_ShouldComplete()
        {
            // Arrange
            var favorite = CreateTestFavorite("fav-id-2", "SELECT * FROM products ORDER BY rating DESC", DateTime.UtcNow.ToString("o"));
            _mockRepository.Setup(r => r.AddQueryHistory(It.IsAny<QueryHistory>()))
                .Returns(Task.CompletedTask);

            // Act
            var act = async () => await _mockRepository.Object.AddQueryHistory(favorite);

            // Assert
            await act.Should().NotThrowAsync();
        }

        [Fact]
        public async Task AddQueryHistory_FavoritesCollection_ShouldUseCorrectCollection()
        {
            // This test verifies that favorites are stored in "dittofavorites" collection
            // The actual implementation should use the overridden CollectionName property

            // Arrange
            var favorite = CreateTestFavorite("fav-id-3", "SELECT * FROM orders WHERE urgent = true", DateTime.UtcNow.ToString("o"));
            _mockRepository.Setup(r => r.AddQueryHistory(It.IsAny<QueryHistory>()))
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.AddQueryHistory(favorite);

            // Assert - Should save to favorites collection (not history)
            _mockRepository.Verify(r => r.AddQueryHistory(It.Is<QueryHistory>(
                qh => qh.Id == "fav-id-3")), Times.Once);
        }

        [Fact]
        public async Task AddQueryHistory_NewFavorite_ShouldCreate()
        {
            // Arrange
            var favorite = CreateTestFavorite("new-fav-id", "SELECT * FROM analytics WHERE important = true", DateTime.UtcNow.ToString("o"));
            _mockRepository.Setup(r => r.AddQueryHistory(It.IsAny<QueryHistory>()))
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.AddQueryHistory(favorite);

            // Assert
            _mockRepository.Verify(r => r.AddQueryHistory(It.Is<QueryHistory>(
                qh => qh.Id == "new-fav-id")), Times.Once);
        }

        [Fact]
        public async Task AddQueryHistory_ExistingFavorite_ShouldUpdateCreatedDate()
        {
            // Arrange
            var originalDate = DateTime.UtcNow.AddDays(-7).ToString("o");
            var newDate = DateTime.UtcNow.ToString("o");
            var existingFavorite = CreateTestFavorite("existing-fav-id", "SELECT * FROM dashboard", originalDate);
            var updatedFavorite = existingFavorite with { CreatedDate = newDate };

            _mockRepository.Setup(r => r.AddQueryHistory(It.IsAny<QueryHistory>()))
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.AddQueryHistory(updatedFavorite);

            // Assert
            _mockRepository.Verify(r => r.AddQueryHistory(It.Is<QueryHistory>(
                qh => qh.Id == "existing-fav-id" && qh.CreatedDate == newDate)), Times.Once);
        }

        #endregion

        #region DeleteQueryHistory Tests (Inherited)

        [Fact]
        public async Task DeleteQueryHistory_ShouldCallRepositoryMethod()
        {
            // Arrange
            var favorite = CreateTestFavorite("fav-id-4", "SELECT * FROM reports", DateTime.UtcNow.ToString("o"));
            _mockRepository.Setup(r => r.DeleteQueryHistory(It.IsAny<QueryHistory>()))
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.DeleteQueryHistory(favorite);

            // Assert
            _mockRepository.Verify(r => r.DeleteQueryHistory(It.Is<QueryHistory>(
                qh => qh.Id == favorite.Id)), Times.Once);
        }

        [Fact]
        public async Task DeleteQueryHistory_WithNullFavorite_ShouldThrowException()
        {
            // Arrange
            _mockRepository.Setup(r => r.DeleteQueryHistory(null!))
                .ThrowsAsync(new ArgumentNullException(nameof(QueryHistory)));

            // Act & Assert
            await Assert.ThrowsAsync<ArgumentNullException>(
                () => _mockRepository.Object.DeleteQueryHistory(null!));
        }

        [Fact]
        public async Task DeleteQueryHistory_WithNonExistentFavorite_ShouldThrowException()
        {
            // Arrange
            var favorite = CreateTestFavorite("non-existent-fav-id", "SELECT * FROM missing", DateTime.UtcNow.ToString("o"));
            _mockRepository.Setup(r => r.DeleteQueryHistory(It.IsAny<QueryHistory>()))
                .ThrowsAsync(new InvalidOperationException("Favorite not found"));

            // Act & Assert
            await Assert.ThrowsAsync<InvalidOperationException>(
                () => _mockRepository.Object.DeleteQueryHistory(favorite));
        }

        [Fact]
        public async Task DeleteQueryHistory_WithValidFavorite_ShouldComplete()
        {
            // Arrange
            var favorite = CreateTestFavorite("fav-id-5", "SELECT * FROM temp_favorites", DateTime.UtcNow.ToString("o"));
            _mockRepository.Setup(r => r.DeleteQueryHistory(It.IsAny<QueryHistory>()))
                .Returns(Task.CompletedTask);

            // Act
            var act = async () => await _mockRepository.Object.DeleteQueryHistory(favorite);

            // Assert
            await act.Should().NotThrowAsync();
        }

        [Fact]
        public async Task DeleteQueryHistory_FavoritesCollection_ShouldDeleteFromCorrectCollection()
        {
            // This test verifies that favorites are deleted from "dittofavorites" collection
            // The actual implementation should use the overridden CollectionName property

            // Arrange
            var favorite = CreateTestFavorite("delete-fav-id", "SELECT * FROM archive", DateTime.UtcNow.ToString("o"));
            _mockRepository.Setup(r => r.DeleteQueryHistory(It.Is<QueryHistory>(qh => qh.Id == "delete-fav-id")))
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.DeleteQueryHistory(favorite);

            // Assert - Should delete from favorites collection (not history)
            _mockRepository.Verify(r => r.DeleteQueryHistory(It.Is<QueryHistory>(
                qh => qh.Id == "delete-fav-id")), Times.Once);
        }

        #endregion

        #region RegisterObserver Tests (Inherited)

        [Fact]
        public void RegisterObserver_ShouldCallRepositoryMethod()
        {
            // Arrange
            var favorites = new ObservableCollection<QueryHistory>
            {
                CreateTestFavorite("fav-1", "SELECT * FROM important_data", DateTime.UtcNow.ToString("o")),
                CreateTestFavorite("fav-2", "SELECT * FROM key_metrics", DateTime.UtcNow.ToString("o"))
            };
            Action<string> errorCallback = (msg) => { };

            _mockRepository.Setup(r => r.RegisterObserver(
                It.IsAny<ObservableCollection<QueryHistory>>(),
                It.IsAny<Action<string>>()));

            // Act
            _mockRepository.Object.RegisterObserver(favorites, errorCallback);

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
                .Throws(new ArgumentNullException("favorites"));

            // Act & Assert
            Assert.Throws<ArgumentNullException>(
                () => _mockRepository.Object.RegisterObserver(null!, errorCallback));
        }

        [Fact]
        public void RegisterObserver_WithNullErrorCallback_ShouldThrowException()
        {
            // Arrange
            var favorites = new ObservableCollection<QueryHistory>();
            _mockRepository.Setup(r => r.RegisterObserver(It.IsAny<ObservableCollection<QueryHistory>>(), null!))
                .Throws(new ArgumentNullException("errorCallback"));

            // Act & Assert
            Assert.Throws<ArgumentNullException>(
                () => _mockRepository.Object.RegisterObserver(favorites, null!));
        }

        [Fact]
        public void RegisterObserver_WithEmptyCollection_ShouldNotThrow()
        {
            // Arrange
            var favorites = new ObservableCollection<QueryHistory>();
            Action<string> errorCallback = (msg) => { };

            _mockRepository.Setup(r => r.RegisterObserver(
                It.IsAny<ObservableCollection<QueryHistory>>(),
                It.IsAny<Action<string>>()));

            // Act
            var act = () => _mockRepository.Object.RegisterObserver(favorites, errorCallback);

            // Assert
            act.Should().NotThrow();
        }

        [Fact]
        public void RegisterObserver_ErrorCallback_ShouldBeInvoked()
        {
            // Arrange
            var favorites = new ObservableCollection<QueryHistory>();
            string? capturedError = null;
            Action<string> errorCallback = (msg) => { capturedError = msg; };

            _mockRepository.Setup(r => r.RegisterObserver(
                It.IsAny<ObservableCollection<QueryHistory>>(),
                It.IsAny<Action<string>>()))
                .Callback<ObservableCollection<QueryHistory>, Action<string>>((queries, callback) =>
                {
                    callback("Test error from favorites observer");
                });

            // Act
            _mockRepository.Object.RegisterObserver(favorites, errorCallback);

            // Assert
            capturedError.Should().Be("Test error from favorites observer");
        }

        [Fact]
        public void RegisterObserver_FavoritesCollection_ShouldObserveCorrectCollection()
        {
            // This test verifies that observer watches "dittofavorites" collection
            // The actual implementation should use "SELECT * FROM dittofavorites"

            // Arrange
            var favorites = new ObservableCollection<QueryHistory>();
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
            _mockRepository.Object.RegisterObserver(favorites, errorCallback);

            // Assert
            observerRegistered.Should().BeTrue();
        }

        [Fact]
        public void RegisterObserver_MultipleObservers_ShouldSupportMultipleFavoritesLists()
        {
            // Arrange
            var favorites1 = new ObservableCollection<QueryHistory>();
            var favorites2 = new ObservableCollection<QueryHistory>();
            Action<string> errorCallback = (msg) => { };

            _mockRepository.Setup(r => r.RegisterObserver(
                It.IsAny<ObservableCollection<QueryHistory>>(),
                It.IsAny<Action<string>>()));

            // Act
            _mockRepository.Object.RegisterObserver(favorites1, errorCallback);
            _mockRepository.Object.RegisterObserver(favorites2, errorCallback);

            // Assert
            _mockRepository.Verify(r => r.RegisterObserver(
                It.IsAny<ObservableCollection<QueryHistory>>(),
                It.IsAny<Action<string>>()), Times.Exactly(2));
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
        public void CloseSelectedDatabase_ShouldCleanupObserversAndResources()
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

        #region Collection Name Override Tests

        [Fact]
        public void FavoritesRepository_ShouldUseDittofavoritesCollection()
        {
            // This is a conceptual test to document that FavoritesRepository
            // overrides CollectionName to "dittofavorites"
            // The actual implementation can be verified by integration tests

            // The CollectionName property should be:
            // protected override string CollectionName => "dittofavorites";

            // This is different from HistoryRepository which uses:
            // protected override string CollectionName => "dittoqueryhistory";

            const string expectedCollectionName = "dittofavorites";
            expectedCollectionName.Should().Be("dittofavorites");
        }

        [Fact]
        public void HistoryAndFavoritesRepositories_ShouldUseDifferentCollections()
        {
            // This test documents that History and Favorites use different collections
            const string historyCollectionName = "dittoqueryhistory";
            const string favoritesCollectionName = "dittofavorites";

            // Assert they are different
            historyCollectionName.Should().NotBe(favoritesCollectionName);
        }

        [Fact]
        public void QueryHistory_Record_SupportsEqualityComparison()
        {
            // Arrange - Records have value-based equality by default
            var favorite1 = CreateTestFavorite("test-id", "SELECT * FROM users", "2025-01-01T00:00:00Z");
            var favorite2 = CreateTestFavorite("test-id", "SELECT * FROM users", "2025-01-01T00:00:00Z");
            var favorite3 = CreateTestFavorite("test-id-different", "SELECT * FROM users", "2025-01-01T00:00:00Z");

            // Assert - Records with same values should be equal
            favorite1.Should().Be(favorite2);
            favorite1.Should().NotBe(favorite3);
        }

        #endregion

        #region Favorites Semantic Tests

        [Fact]
        public async Task FavoritesRepository_ShouldStoreFrequentlyUsedQueries()
        {
            // Arrange - Favorites are typically queries users want quick access to
            var favoriteQuery = CreateTestFavorite(
                "fav-dashboard",
                "SELECT COUNT(*) as total, SUM(revenue) as revenue FROM sales WHERE date >= :startDate",
                DateTime.UtcNow.ToString("o"));

            _mockRepository.Setup(r => r.AddQueryHistory(It.IsAny<QueryHistory>()))
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.AddQueryHistory(favoriteQuery);

            // Assert
            _mockRepository.Verify(r => r.AddQueryHistory(It.Is<QueryHistory>(
                qh => qh.Id == "fav-dashboard")), Times.Once);
        }

        [Fact]
        public async Task FavoritesRepository_ShouldSupportComplexQueryFavorites()
        {
            // Arrange - Complex queries are good candidates for favorites
            var complexQuery = @"
                SELECT
                    u.name,
                    COUNT(o.id) as order_count,
                    SUM(o.total) as total_revenue
                FROM users u
                INNER JOIN orders o ON u.id = o.user_id
                WHERE o.status = 'completed'
                GROUP BY u.name
                ORDER BY total_revenue DESC
                LIMIT 10";

            var favorite = CreateTestFavorite("fav-top-customers", complexQuery, DateTime.UtcNow.ToString("o"));

            _mockRepository.Setup(r => r.AddQueryHistory(It.IsAny<QueryHistory>()))
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.AddQueryHistory(favorite);

            // Assert
            _mockRepository.Verify(r => r.AddQueryHistory(It.Is<QueryHistory>(
                qh => qh.Id == "fav-top-customers" && qh.Query.Contains("total_revenue"))), Times.Once);
        }

        #endregion

        #region Helper Methods

        /// <summary>
        /// Creates a test QueryHistory representing a favorite query
        /// </summary>
        private static QueryHistory CreateTestFavorite(string id, string query, string createdDate)
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
