using EdgeStudio.Shared.Models;
using FluentAssertions;
using System;
using Xunit;

namespace EdgeStudioTests
{
    public class QueryMetricTests
    {
        private static QueryMetric Make(string explainOutput = "", double ms = 0, int resultCount = 0) =>
            new(Guid.NewGuid().ToString(), "SELECT * FROM t", ms, resultCount, explainOutput, DateTime.UtcNow);

        [Fact]
        public void UsedIndex_WhenExplainContainsIndex_ReturnsTrue()
        {
            var metric = Make(explainOutput: "scan using index on collection");

            metric.UsedIndex.Should().BeTrue();
        }

        [Fact]
        public void UsedIndex_WhenExplainEmpty_ReturnsFalse()
        {
            var metric = Make(explainOutput: "");

            metric.UsedIndex.Should().BeFalse();
        }

        [Fact]
        public void FormattedExecutionTime_SubMs_ReturnsLessThan1Ms()
        {
            var metric = Make(ms: 0.5);

            metric.FormattedExecutionTime.Should().Be("<1 ms");
        }

        [Fact]
        public void FormattedExecutionTime_MillisecondRange_ReturnsMsString()
        {
            var metric = Make(ms: 42.7);

            metric.FormattedExecutionTime.Should().Be("43 ms");
        }

        [Fact]
        public void FormattedExecutionTime_OverOneSecond_ReturnsSeconds()
        {
            var metric = Make(ms: 1500);

            metric.FormattedExecutionTime.Should().Be("1.50 s");
        }
    }
}
