using System;
using System.Collections.Generic;
using System.Text.Json;
using EdgeStudio.Shared.Data;
using FluentAssertions;
using Xunit;

namespace EdgeStudioTests
{
    public class ImportServiceValidationTests
    {
        [Fact]
        public void ValidateJson_ValidArray_ReturnsCount()
        {
            var service = CreateService();
            var json = """[{"_id": "1", "name": "Alice"}, {"_id": "2", "name": "Bob"}]""";

            var count = service.ValidateJson(json);

            count.Should().Be(2);
        }

        [Fact]
        public void ValidateJson_InvalidJson_Throws()
        {
            var service = CreateService();

            var act = () => service.ValidateJson("not json");

            act.Should().Throw<InvalidOperationException>()
                .WithMessage("Invalid JSON:*");
        }

        [Fact]
        public void ValidateJson_NotArray_Throws()
        {
            var service = CreateService();

            var act = () => service.ValidateJson("""{"_id": "1"}""");

            act.Should().Throw<InvalidOperationException>()
                .WithMessage("JSON must be an array*");
        }

        [Fact]
        public void ValidateJson_MissingId_Throws()
        {
            var service = CreateService();
            var json = """[{"name": "Alice"}]""";

            var act = () => service.ValidateJson(json);

            act.Should().Throw<InvalidOperationException>()
                .WithMessage("*missing required '_id' field*");
        }

        [Fact]
        public void ValidateJson_EmptyArray_Throws()
        {
            var service = CreateService();

            var act = () => service.ValidateJson("[]");

            act.Should().Throw<InvalidOperationException>()
                .WithMessage("*empty*");
        }

        [Fact]
        public void ValidateJson_NonObjectElement_Throws()
        {
            var service = CreateService();
            var json = """[42, "text"]""";

            var act = () => service.ValidateJson(json);

            act.Should().Throw<InvalidOperationException>()
                .WithMessage("*not a JSON object*");
        }

        private static ImportService CreateService()
        {
            // DittoManager is not needed for validation-only tests
            return new ImportService(null!);
        }
    }
}
