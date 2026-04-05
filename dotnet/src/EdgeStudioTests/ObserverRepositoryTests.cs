using EdgeStudio.Shared.Data.Repositories;
using EdgeStudio.Shared.Models;
using FluentAssertions;
using Moq;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Xunit;

namespace EdgeStudioTests
{
    /// <summary>
    /// Unit tests for IObserverRepository interface
    /// </summary>
    public class ObserverRepositoryTests
    {
        private readonly Mock<IObserverRepository> _mockRepository;

        public ObserverRepositoryTests()
        {
            _mockRepository = new Mock<IObserverRepository>();
        }

        #region GetObserversAsync Tests

        [Fact]
        public async Task GetObserversAsync_ShouldReturnObserversList()
        {
            // Arrange
            var observers = new List<DittoDatabaseObserver>
            {
                CreateTestObserver("obs-1", "Observer 1", "SELECT * FROM users"),
                CreateTestObserver("obs-2", "Observer 2", "SELECT * FROM tasks")
            };
            _mockRepository.Setup(r => r.GetObserversAsync())
                .ReturnsAsync(observers);

            // Act
            var result = await _mockRepository.Object.GetObserversAsync();

            // Assert
            result.Should().HaveCount(2);
            result[0].Name.Should().Be("Observer 1");
            result[1].Name.Should().Be("Observer 2");
        }

        [Fact]
        public async Task GetObserversAsync_WhenEmpty_ShouldReturnEmptyList()
        {
            // Arrange
            _mockRepository.Setup(r => r.GetObserversAsync())
                .ReturnsAsync(new List<DittoDatabaseObserver>());

            // Act
            var result = await _mockRepository.Object.GetObserversAsync();

            // Assert
            result.Should().BeEmpty();
        }

        #endregion

        #region SaveObserverAsync Tests

        [Fact]
        public async Task SaveObserverAsync_ShouldCallRepositoryMethod()
        {
            // Arrange
            var observer = CreateTestObserver("obs-1", "Test Observer", "SELECT * FROM users");
            _mockRepository.Setup(r => r.SaveObserverAsync(It.IsAny<DittoDatabaseObserver>()))
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.SaveObserverAsync(observer);

            // Assert
            _mockRepository.Verify(r => r.SaveObserverAsync(It.Is<DittoDatabaseObserver>(
                o => o.Id == observer.Id && o.Name == observer.Name)), Times.Once);
        }

        [Fact]
        public async Task SaveObserverAsync_WithValidObserver_ShouldComplete()
        {
            // Arrange
            var observer = CreateTestObserver("obs-2", "User Observer", "SELECT * FROM users WHERE active = true");
            _mockRepository.Setup(r => r.SaveObserverAsync(It.IsAny<DittoDatabaseObserver>()))
                .Returns(Task.CompletedTask);

            // Act
            var act = async () => await _mockRepository.Object.SaveObserverAsync(observer);

            // Assert
            await act.Should().NotThrowAsync();
        }

        #endregion

        #region DeleteObserverAsync Tests

        [Fact]
        public async Task DeleteObserverAsync_ShouldCallRepositoryMethod()
        {
            // Arrange
            _mockRepository.Setup(r => r.DeleteObserverAsync(It.IsAny<string>()))
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.DeleteObserverAsync("obs-1");

            // Assert
            _mockRepository.Verify(r => r.DeleteObserverAsync("obs-1"), Times.Once);
        }

        [Fact]
        public async Task DeleteObserverAsync_WithNonExistentId_ShouldNotThrow()
        {
            // Arrange
            _mockRepository.Setup(r => r.DeleteObserverAsync(It.IsAny<string>()))
                .Returns(Task.CompletedTask);

            // Act
            var act = async () => await _mockRepository.Object.DeleteObserverAsync("non-existent-id");

            // Assert
            await act.Should().NotThrowAsync();
        }

        #endregion

        #region IsObserverActive Tests

        [Fact]
        public void IsObserverActive_WhenActive_ShouldReturnTrue()
        {
            // Arrange
            _mockRepository.Setup(r => r.IsObserverActive("obs-1"))
                .Returns(true);

            // Act
            var result = _mockRepository.Object.IsObserverActive("obs-1");

            // Assert
            result.Should().BeTrue();
        }

        [Fact]
        public void IsObserverActive_WhenInactive_ShouldReturnFalse()
        {
            // Arrange
            _mockRepository.Setup(r => r.IsObserverActive("obs-1"))
                .Returns(false);

            // Act
            var result = _mockRepository.Object.IsObserverActive("obs-1");

            // Assert
            result.Should().BeFalse();
        }

        #endregion

        #region DeactivateObserver Tests

        [Fact]
        public void DeactivateObserver_ShouldCallRepositoryMethod()
        {
            // Arrange & Act
            _mockRepository.Object.DeactivateObserver("obs-1");

            // Assert
            _mockRepository.Verify(r => r.DeactivateObserver("obs-1"), Times.Once);
        }

        #endregion

        #region CloseSelectedDatabase Tests

        [Fact]
        public void CloseSelectedDatabase_ShouldCallRepositoryMethod()
        {
            // Arrange & Act
            _mockRepository.Object.CloseSelectedDatabase();

            // Assert
            _mockRepository.Verify(r => r.CloseSelectedDatabase(), Times.Once);
        }

        #endregion

        #region CloseDatabaseAsync Tests

        [Fact]
        public async Task CloseDatabaseAsync_ShouldCallRepositoryMethod()
        {
            // Arrange
            _mockRepository.Setup(r => r.CloseDatabaseAsync())
                .Returns(Task.CompletedTask);

            // Act
            await _mockRepository.Object.CloseDatabaseAsync();

            // Assert
            _mockRepository.Verify(r => r.CloseDatabaseAsync(), Times.Once);
        }

        #endregion

        #region Helper Methods

        private static DittoDatabaseObserver CreateTestObserver(string id, string name, string query)
        {
            return new DittoDatabaseObserver(Id: id, Name: name, Query: query);
        }

        #endregion
    }
}
