using EdgeStudio.Shared.Data.Repositories;
using EdgeStudio.Shared.Models;
using FluentAssertions;
using Moq;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Xunit;

namespace EdgeStudioTests
{
    /// <summary>
    /// Unit tests for ISubscriptionRepository interface
    /// </summary>
    public class SubscriptionRepositoryTests
    {
        private readonly Mock<ISubscriptionRepository> _mockRepository;

        public SubscriptionRepositoryTests()
        {
            _mockRepository = new Mock<ISubscriptionRepository>();
        }

        #region SaveDittoSubscription Tests

        [Fact]
        public async Task SaveDittoSubscription_ShouldCallRepositoryMethod()
        {
            // Arrange
            var subscription = CreateTestSubscription("sub-id-1", "Test Subscription", "SELECT * FROM users");
            _mockRepository.Setup(r => r.SaveDittoSubscription(It.IsAny<DittoDatabaseSubscription>()))
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.SaveDittoSubscription(subscription);

            // Assert
            _mockRepository.Verify(r => r.SaveDittoSubscription(It.Is<DittoDatabaseSubscription>(
                s => s.Id == subscription.Id && s.Name == subscription.Name)), Times.Once);
        }

        [Fact]
        public async Task SaveDittoSubscription_WithNullSubscription_ShouldThrowException()
        {
            // Arrange
            _mockRepository.Setup(r => r.SaveDittoSubscription(null!))
                .ThrowsAsync(new ArgumentNullException(nameof(DittoDatabaseSubscription)));

            // Act & Assert
            await Assert.ThrowsAsync<ArgumentNullException>(
                () => _mockRepository.Object.SaveDittoSubscription(null!));
        }

        [Fact]
        public async Task SaveDittoSubscription_WithValidSubscription_ShouldComplete()
        {
            // Arrange
            var subscription = CreateTestSubscription("sub-id-2", "User Subscription", "SELECT * FROM users WHERE active = true");
            _mockRepository.Setup(r => r.SaveDittoSubscription(It.IsAny<DittoDatabaseSubscription>()))
                .Returns(Task.CompletedTask);

            // Act
            var act = async () => await _mockRepository.Object.SaveDittoSubscription(subscription);

            // Assert
            await act.Should().NotThrowAsync();
        }

        [Fact]
        public async Task SaveDittoSubscription_WithEmptyQuery_ShouldThrowException()
        {
            // Arrange
            var subscription = CreateTestSubscription("sub-id-3", "Empty Query Sub", "");
            _mockRepository.Setup(r => r.SaveDittoSubscription(It.Is<DittoDatabaseSubscription>(s => string.IsNullOrEmpty(s.Query))))
                .ThrowsAsync(new ArgumentException("Query cannot be empty"));

            // Act & Assert
            await Assert.ThrowsAsync<ArgumentException>(
                () => _mockRepository.Object.SaveDittoSubscription(subscription));
        }

        [Fact]
        public async Task SaveDittoSubscription_NewSubscription_ShouldCreate()
        {
            // Arrange
            var subscription = CreateTestSubscription("new-sub-id", "New Subscription", "SELECT * FROM orders");
            _mockRepository.Setup(r => r.SaveDittoSubscription(It.IsAny<DittoDatabaseSubscription>()))
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.SaveDittoSubscription(subscription);

            // Assert
            _mockRepository.Verify(r => r.SaveDittoSubscription(It.Is<DittoDatabaseSubscription>(
                s => s.Id == "new-sub-id")), Times.Once);
        }

        [Fact]
        public async Task SaveDittoSubscription_ExistingSubscription_ShouldUpdate()
        {
            // Arrange
            var existingSubscription = CreateTestSubscription("existing-id", "Old Name", "SELECT * FROM products");
            var updatedSubscription = existingSubscription with { Name = "Updated Name", Query = "SELECT * FROM products WHERE price > 100" };

            _mockRepository.Setup(r => r.SaveDittoSubscription(It.IsAny<DittoDatabaseSubscription>()))
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.SaveDittoSubscription(updatedSubscription);

            // Assert
            _mockRepository.Verify(r => r.SaveDittoSubscription(It.Is<DittoDatabaseSubscription>(
                s => s.Id == "existing-id" && s.Name == "Updated Name")), Times.Once);
        }

        #endregion

        #region GetDittoSubscriptions Tests

        [Fact]
        public async Task GetDittoSubscriptions_ShouldReturnListOfSubscriptions()
        {
            // Arrange
            var subscriptions = new List<DittoDatabaseSubscription>
            {
                CreateTestSubscription("sub-1", "Subscription 1", "SELECT * FROM users"),
                CreateTestSubscription("sub-2", "Subscription 2", "SELECT * FROM orders"),
                CreateTestSubscription("sub-3", "Subscription 3", "SELECT * FROM products")
            };

            _mockRepository.Setup(r => r.GetDittoSubscriptions())
                .ReturnsAsync(subscriptions);

            // Act
            var result = await _mockRepository.Object.GetDittoSubscriptions();

            // Assert
            result.Should().NotBeNull();
            result.Should().HaveCount(3);
            result.Should().BeEquivalentTo(subscriptions);
        }

        [Fact]
        public async Task GetDittoSubscriptions_WhenEmpty_ShouldReturnEmptyList()
        {
            // Arrange
            _mockRepository.Setup(r => r.GetDittoSubscriptions())
                .ReturnsAsync(new List<DittoDatabaseSubscription>());

            // Act
            var result = await _mockRepository.Object.GetDittoSubscriptions();

            // Assert
            result.Should().NotBeNull();
            result.Should().BeEmpty();
        }

        [Fact]
        public async Task GetDittoSubscriptions_ShouldCallRepositoryMethod()
        {
            // Arrange
            _mockRepository.Setup(r => r.GetDittoSubscriptions())
                .ReturnsAsync(new List<DittoDatabaseSubscription>());

            // Act
            await _mockRepository.Object.GetDittoSubscriptions();

            // Assert
            _mockRepository.Verify(r => r.GetDittoSubscriptions(), Times.Once);
        }

        [Fact]
        public async Task GetDittoSubscriptions_OnError_ShouldThrowException()
        {
            // Arrange
            _mockRepository.Setup(r => r.GetDittoSubscriptions())
                .ThrowsAsync(new InvalidOperationException("Failed to retrieve subscriptions"));

            // Act & Assert
            await Assert.ThrowsAsync<InvalidOperationException>(
                () => _mockRepository.Object.GetDittoSubscriptions());
        }

        [Fact]
        public async Task GetDittoSubscriptions_ShouldReturnSubscriptionsInOrder()
        {
            // Arrange
            var subscriptions = new List<DittoDatabaseSubscription>
            {
                CreateTestSubscription("sub-1", "Alpha", "SELECT * FROM alpha"),
                CreateTestSubscription("sub-2", "Beta", "SELECT * FROM beta"),
                CreateTestSubscription("sub-3", "Gamma", "SELECT * FROM gamma")
            };

            _mockRepository.Setup(r => r.GetDittoSubscriptions())
                .ReturnsAsync(subscriptions);

            // Act
            var result = await _mockRepository.Object.GetDittoSubscriptions();

            // Assert
            result.Should().ContainInOrder(subscriptions);
            result.First().Name.Should().Be("Alpha");
            result.Last().Name.Should().Be("Gamma");
        }

        [Fact]
        public async Task GetDittoSubscriptions_ShouldReturnCompleteSubscriptionData()
        {
            // Arrange
            var subscription = CreateTestSubscription("complete-sub", "Complete Subscription", "SELECT * FROM complete");
            var subscriptions = new List<DittoDatabaseSubscription> { subscription };

            _mockRepository.Setup(r => r.GetDittoSubscriptions())
                .ReturnsAsync(subscriptions);

            // Act
            var result = await _mockRepository.Object.GetDittoSubscriptions();

            // Assert
            var returnedSubscription = result.First();
            returnedSubscription.Id.Should().Be("complete-sub");
            returnedSubscription.Name.Should().Be("Complete Subscription");
            returnedSubscription.Query.Should().Be("SELECT * FROM complete");
        }

        #endregion

        #region DeleteDittoSubscription Tests

        [Fact]
        public async Task DeleteDittoSubscription_ShouldCallRepositoryMethod()
        {
            // Arrange
            var subscription = CreateTestSubscription("delete-id-1", "Delete Test", "SELECT * FROM test");
            _mockRepository.Setup(r => r.DeleteDittoSubscription(It.IsAny<DittoDatabaseSubscription>()))
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.DeleteDittoSubscription(subscription);

            // Assert
            _mockRepository.Verify(r => r.DeleteDittoSubscription(It.Is<DittoDatabaseSubscription>(
                s => s.Id == subscription.Id)), Times.Once);
        }

        [Fact]
        public async Task DeleteDittoSubscription_WithNullSubscription_ShouldThrowException()
        {
            // Arrange
            _mockRepository.Setup(r => r.DeleteDittoSubscription(null!))
                .ThrowsAsync(new ArgumentNullException(nameof(DittoDatabaseSubscription)));

            // Act & Assert
            await Assert.ThrowsAsync<ArgumentNullException>(
                () => _mockRepository.Object.DeleteDittoSubscription(null!));
        }

        [Fact]
        public async Task DeleteDittoSubscription_WithValidSubscription_ShouldComplete()
        {
            // Arrange
            var subscription = CreateTestSubscription("delete-id-2", "Valid Delete", "SELECT * FROM data");
            _mockRepository.Setup(r => r.DeleteDittoSubscription(It.IsAny<DittoDatabaseSubscription>()))
                .Returns(Task.CompletedTask);

            // Act
            var act = async () => await _mockRepository.Object.DeleteDittoSubscription(subscription);

            // Assert
            await act.Should().NotThrowAsync();
        }

        [Fact]
        public async Task DeleteDittoSubscription_WithNonExistentSubscription_ShouldThrowException()
        {
            // Arrange
            var subscription = CreateTestSubscription("non-existent-id", "Non Existent", "SELECT * FROM nowhere");
            _mockRepository.Setup(r => r.DeleteDittoSubscription(It.IsAny<DittoDatabaseSubscription>()))
                .ThrowsAsync(new InvalidOperationException("Subscription not found"));

            // Act & Assert
            await Assert.ThrowsAsync<InvalidOperationException>(
                () => _mockRepository.Object.DeleteDittoSubscription(subscription));
        }

        [Fact]
        public async Task DeleteDittoSubscription_AfterDeletion_ShouldNotExistInRepository()
        {
            // Arrange
            var subscription = CreateTestSubscription("delete-id-3", "To Be Deleted", "SELECT * FROM temp");
            var subscriptions = new List<DittoDatabaseSubscription> { subscription };

            _mockRepository.Setup(r => r.GetDittoSubscriptions())
                .ReturnsAsync(subscriptions);

            _mockRepository.Setup(r => r.DeleteDittoSubscription(It.IsAny<DittoDatabaseSubscription>()))
                .Callback<DittoDatabaseSubscription>(s => subscriptions.Remove(s))
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.DeleteDittoSubscription(subscription);
            _mockRepository.Setup(r => r.GetDittoSubscriptions())
                .ReturnsAsync(subscriptions);
            var result = await _mockRepository.Object.GetDittoSubscriptions();

            // Assert
            result.Should().NotContain(subscription);
            result.Should().BeEmpty();
        }

        #endregion

        #region Integration-Style Tests

        [Fact]
        public async Task FullLifecycle_CreateGetUpdateDelete_ShouldWork()
        {
            // Arrange
            var subscriptions = new List<DittoDatabaseSubscription>();
            var subscription = CreateTestSubscription("lifecycle-id", "Lifecycle Test", "SELECT * FROM lifecycle");

            // Setup Save
            _mockRepository.Setup(r => r.SaveDittoSubscription(It.IsAny<DittoDatabaseSubscription>()))
                .Callback<DittoDatabaseSubscription>(s =>
                {
                    var existing = subscriptions.FirstOrDefault(sub => sub.Id == s.Id);
                    if (existing != null)
                    {
                        subscriptions.Remove(existing);
                    }
                    subscriptions.Add(s);
                })
                .Returns(Task.CompletedTask);

            // Setup Get
            _mockRepository.Setup(r => r.GetDittoSubscriptions())
                .ReturnsAsync(() => subscriptions.ToList());

            // Setup Delete
            _mockRepository.Setup(r => r.DeleteDittoSubscription(It.IsAny<DittoDatabaseSubscription>()))
                .Callback<DittoDatabaseSubscription>(s => subscriptions.Remove(s))
                .Returns(Task.CompletedTask);

            // Act & Assert - Create
            await _mockRepository.Object.SaveDittoSubscription(subscription);
            var afterCreate = await _mockRepository.Object.GetDittoSubscriptions();
            afterCreate.Should().HaveCount(1);
            afterCreate.First().Name.Should().Be("Lifecycle Test");

            // Act & Assert - Update
            var updatedSubscription = subscription with { Name = "Updated Lifecycle Test" };
            await _mockRepository.Object.SaveDittoSubscription(updatedSubscription);
            var afterUpdate = await _mockRepository.Object.GetDittoSubscriptions();
            afterUpdate.Should().HaveCount(1);
            afterUpdate.First().Name.Should().Be("Updated Lifecycle Test");

            // Act & Assert - Delete
            await _mockRepository.Object.DeleteDittoSubscription(updatedSubscription);
            var afterDelete = await _mockRepository.Object.GetDittoSubscriptions();
            afterDelete.Should().BeEmpty();
        }

        [Fact]
        public async Task MultipleSubscriptions_SaveAndRetrieve_ShouldMaintainAllData()
        {
            // Arrange
            var subscriptions = new List<DittoDatabaseSubscription>
            {
                CreateTestSubscription("multi-1", "Multi Sub 1", "SELECT * FROM table1"),
                CreateTestSubscription("multi-2", "Multi Sub 2", "SELECT * FROM table2"),
                CreateTestSubscription("multi-3", "Multi Sub 3", "SELECT * FROM table3")
            };

            _mockRepository.Setup(r => r.GetDittoSubscriptions())
                .ReturnsAsync(subscriptions);

            // Act
            var result = await _mockRepository.Object.GetDittoSubscriptions();

            // Assert
            result.Should().HaveCount(3);
            result.Select(s => s.Id).Should().BeEquivalentTo(new[] { "multi-1", "multi-2", "multi-3" });
            result.Select(s => s.Name).Should().BeEquivalentTo(new[] { "Multi Sub 1", "Multi Sub 2", "Multi Sub 3" });
        }

        #endregion

        #region Helper Methods

        /// <summary>
        /// Creates a test DittoDatabaseSubscription with the specified ID, name, and query
        /// </summary>
        private static DittoDatabaseSubscription CreateTestSubscription(string id, string name, string query)
        {
            return new DittoDatabaseSubscription(
                Id: id,
                Name: name,
                Query: query
            );
        }

        #endregion
    }
}
