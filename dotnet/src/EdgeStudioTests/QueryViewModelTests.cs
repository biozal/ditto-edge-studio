using EdgeStudio.Shared.Data.Repositories;
using EdgeStudio.Shared.Models;
using EdgeStudio.ViewModels;
using FluentAssertions;
using Moq;
using Xunit;

namespace EdgeStudioTests
{
    public class QueryViewModelTests
    {
        private readonly Mock<ICollectionsRepository> _mockRepo = new();

        private QueryViewModel CreateSut() => new(_mockRepo.Object);

        private static DittoDatabaseConfig MakeConfig(string httpApiUrl = "", string httpApiKey = "") =>
            new("id", "Test", "db-id", "token", "https://auth", httpApiUrl, httpApiKey,
                "online", false);

        #region HTTP Mode Tests

        [Fact]
        public void SetDatabaseConfig_WithHttpConfig_MakesHttpModeAvailable()
        {
            // Arrange
            var sut = CreateSut();
            // Prime the collection with a query document (OnInitialize not called in unit tests)
            sut.NewQueryCommand.Execute(null);
            var config = MakeConfig(httpApiUrl: "https://api.example.com", httpApiKey: "secret");

            // Act
            sut.SetDatabaseConfig(config);

            // Assert
            sut.QueryDocuments[0].AvailableQueryModes.Should().Contain("HTTP");
        }

        [Fact]
        public void SetDatabaseConfig_WithoutHttpConfig_OnlyShowsLocalMode()
        {
            // Arrange
            var sut = CreateSut();
            // Prime the collection with a query document (OnInitialize not called in unit tests)
            sut.NewQueryCommand.Execute(null);
            var config = MakeConfig(httpApiUrl: "", httpApiKey: "");

            // Act
            sut.SetDatabaseConfig(config);

            // Assert
            sut.QueryDocuments[0].AvailableQueryModes.Should().ContainSingle()
                .Which.Should().Be("Local");
        }

        [Fact]
        public void SetDatabaseConfig_WithNullConfig_OnlyShowsLocalMode()
        {
            // Arrange
            var sut = CreateSut();
            // Prime the collection with a query document (OnInitialize not called in unit tests)
            sut.NewQueryCommand.Execute(null);
            sut.SetDatabaseConfig(MakeConfig("https://api", "key")); // first add HTTP

            // Act
            sut.SetDatabaseConfig(null);

            // Assert
            sut.QueryDocuments[0].AvailableQueryModes.Should().NotContain("HTTP");
        }

        #endregion

        #region Pagination Tests

        [Fact]
        public void NextPage_WhenNotLastPage_IncrementsPage()
        {
            // Arrange
            var sut = CreateSut();
            sut.TotalResultCount = 100;
            sut.PageSize = 25; // PageCount = 4
            sut.CurrentPage = 1;

            // Act
            sut.NextPageCommand.Execute(null);

            // Assert
            sut.CurrentPage.Should().Be(2);
        }

        [Fact]
        public void PreviousPage_WhenNotFirstPage_DecrementsPage()
        {
            // Arrange
            var sut = CreateSut();
            sut.TotalResultCount = 100;
            sut.PageSize = 25;
            sut.CurrentPage = 3;

            // Act
            sut.PreviousPageCommand.Execute(null);

            // Assert
            sut.CurrentPage.Should().Be(2);
        }

        [Fact]
        public void NextPage_OnLastPage_DoesNotIncrement()
        {
            // Arrange
            var sut = CreateSut();
            sut.TotalResultCount = 50;
            sut.PageSize = 25; // PageCount = 2
            sut.CurrentPage = 2;

            // Act
            sut.NextPageCommand.Execute(null);

            // Assert
            sut.CurrentPage.Should().Be(2);
        }

        [Fact]
        public void PreviousPage_OnFirstPage_DoesNotDecrement()
        {
            // Arrange
            var sut = CreateSut();
            sut.TotalResultCount = 100;
            sut.PageSize = 25;
            sut.CurrentPage = 1;

            // Act
            sut.PreviousPageCommand.Execute(null);

            // Assert
            sut.CurrentPage.Should().Be(1);
        }

        [Fact]
        public void PageCount_ReflectsTotalCountAndPageSize()
        {
            // Arrange
            var sut = CreateSut();
            sut.TotalResultCount = 75;

            // Act
            sut.PageSize = 25;

            // Assert
            sut.PageCount.Should().Be(3);
        }

        [Fact]
        public void PageCount_WhenZeroResults_ReturnsOne()
        {
            // Arrange
            var sut = CreateSut();
            sut.TotalResultCount = 0;
            sut.PageSize = 25;

            // Assert
            sut.PageCount.Should().Be(1);
        }

        #endregion
    }
}
