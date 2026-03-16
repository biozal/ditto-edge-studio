using EdgeStudio.ViewModels;
using FluentAssertions;
using Xunit;

namespace EdgeStudioTests
{
    public class JsonResultsViewModelTests
    {
        private static JsonResultsViewModel CreateSut() => new();

        [Fact]
        public void SetResults_PopulatesPagedDocuments_WithFirstPage()
        {
            var sut = CreateSut();
            var docs = new[] { "{\"id\":1}", "{\"id\":2}", "{\"id\":3}" };

            sut.SetResults(docs);

            sut.PagedDocuments.Should().HaveCount(3);
        }

        [Fact]
        public void SetResults_TotalCount_ReflectsDocumentCount()
        {
            var sut = CreateSut();
            var docs = new[] { "{\"a\":1}", "{\"a\":2}", "{\"a\":3}", "{\"a\":4}", "{\"a\":5}" };

            sut.SetResults(docs);

            sut.TotalCount.Should().Be(5);
        }

        [Fact]
        public void SetResults_ResetsToPageOne()
        {
            var sut = CreateSut();
            sut.PageSize = 2;
            sut.SetResults(new[] { "a", "b", "c", "d" });
            sut.NextPageCommand.Execute(null);
            sut.CurrentPage.Should().Be(2);

            sut.SetResults(new[] { "x", "y" });

            sut.CurrentPage.Should().Be(1);
        }

        [Fact]
        public void NextPage_ShowsNextPageItems()
        {
            var sut = CreateSut();
            sut.PageSize = 2;
            sut.SetResults(new[] { "{\"n\":1}", "{\"n\":2}", "{\"n\":3}", "{\"n\":4}" });

            sut.NextPageCommand.Execute(null);

            sut.CurrentPage.Should().Be(2);
            sut.PagedDocuments.Should().HaveCount(2);
            sut.PagedDocuments[0].Should().Be("{\"n\":3}");
        }

        [Fact]
        public void PreviousPage_OnFirstPage_DoesNotChange()
        {
            var sut = CreateSut();
            sut.SetResults(new[] { "a", "b" });

            sut.PreviousPageCommand.Execute(null);

            sut.CurrentPage.Should().Be(1);
        }

        [Fact]
        public void SetError_ShowsErrorDocument()
        {
            var sut = CreateSut();

            sut.SetError("something went wrong");

            sut.PagedDocuments.Should().HaveCount(1);
            sut.PagedDocuments[0].Should().Contain("error");
            sut.TotalCount.Should().Be(0);
        }

        [Fact]
        public void SelectDocumentCommand_FiresDocumentSelectedEvent()
        {
            var sut = CreateSut();
            sut.SetResults(new[] { "{\"x\":1}" });

            string? selected = null;
            sut.DocumentSelected += json => selected = json;

            sut.SelectDocumentCommand.Execute("{\"x\":1}");

            selected.Should().Be("{\"x\":1}");
        }

        [Fact]
        public void Clear_RemovesAllData()
        {
            var sut = CreateSut();
            sut.SetResults(new[] { "a", "b", "c" });

            sut.Clear();

            sut.PagedDocuments.Should().BeEmpty();
            sut.TotalCount.Should().Be(0);
        }

        [Fact]
        public void PageCount_ReflectsTotalCountAndPageSize()
        {
            var sut = CreateSut();
            sut.SetResults(Enumerable.Range(0, 75).Select(i => $"{{\"i\":{i}}}").ToArray());
            sut.PageSize = 25;

            sut.PageCount.Should().Be(3);
        }
    }
}
