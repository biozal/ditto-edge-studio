using EdgeStudio.Shared.Data;
using FluentAssertions;
using Xunit;

namespace EdgeStudioTests
{
    public class QueryResultsParserTests
    {
        private static QueryResultsParser CreateSut() => new();

        [Fact]
        public void Parse_EmptyList_ReturnsEmptyTable()
        {
            var sut = CreateSut();

            var result = sut.Parse(Array.Empty<string>());

            result.Columns.Should().BeEmpty();
            result.Rows.Should().BeEmpty();
        }

        [Fact]
        public void Parse_WithSingleDocument_ExtractsAllColumns()
        {
            var sut = CreateSut();
            var docs = new[] { "{\"_id\":\"abc\",\"name\":\"Alice\",\"age\":30}" };

            var result = sut.Parse(docs);

            result.Columns.Should().Contain("_id");
            result.Columns.Should().Contain("name");
            result.Columns.Should().Contain("age");
        }

        [Fact]
        public void Parse_IdColumn_AlwaysFirst()
        {
            var sut = CreateSut();
            var docs = new[] { "{\"name\":\"Alice\",\"_id\":\"abc\",\"age\":30}" };

            var result = sut.Parse(docs);

            result.Columns[0].Should().Be("_id");
        }

        [Fact]
        public void Parse_WithMultipleDocuments_UnionOfAllKeys()
        {
            var sut = CreateSut();
            var docs = new[]
            {
                "{\"_id\":\"1\",\"name\":\"Alice\"}",
                "{\"_id\":\"2\",\"age\":30}"
            };

            var result = sut.Parse(docs);

            result.Columns.Should().Contain("name");
            result.Columns.Should().Contain("age");
            result.Rows.Should().HaveCount(2);
        }

        [Fact]
        public void Parse_NullValue_ShowsEmptyString()
        {
            var sut = CreateSut();
            var docs = new[] { "{\"_id\":\"1\",\"name\":null}" };

            var result = sut.Parse(docs);

            var nameIndex = result.Columns.ToList().IndexOf("name");
            result.Rows[0][nameIndex].Should().Be(string.Empty);
        }

        [Fact]
        public void Parse_NestedObject_SerializedAsCompactJson()
        {
            var sut = CreateSut();
            var docs = new[] { "{\"_id\":\"1\",\"address\":{\"city\":\"NY\"}}" };

            var result = sut.Parse(docs);

            var addrIndex = result.Columns.ToList().IndexOf("address");
            result.Rows[0][addrIndex].Should().Contain("city");
        }

        [Fact]
        public void Parse_ArrayValue_SerializedAsCompactJson()
        {
            var sut = CreateSut();
            var docs = new[] { "{\"_id\":\"1\",\"tags\":[\"a\",\"b\"]}" };

            var result = sut.Parse(docs);

            var tagsIndex = result.Columns.ToList().IndexOf("tags");
            result.Rows[0][tagsIndex].Should().Contain("a");
        }
    }
}
