using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Models;
using FluentAssertions;
using System;
using Xunit;

namespace EdgeStudioTests
{
    public class InMemoryQueryMetricsServiceTests
    {
        private static InMemoryQueryMetricsService CreateSut() => new();

        private static QueryMetric MakeMetric(string query = "SELECT * FROM t", int resultCount = 5) =>
            new(Guid.NewGuid().ToString(), query, 42.0, resultCount, "", DateTime.UtcNow);

        [Fact]
        public void Capture_StoresMetric()
        {
            var sut = CreateSut();
            var metric = MakeMetric();

            sut.Capture(metric);

            sut.GetAll().Should().ContainSingle();
        }

        [Fact]
        public void Latest_ReturnsNewestMetric()
        {
            var sut = CreateSut();
            sut.Capture(MakeMetric("q1"));
            var latest = MakeMetric("q2");
            sut.Capture(latest);

            sut.Latest.Should().Be(latest);
        }

        [Fact]
        public void GetAll_ReturnsMostRecentFirst()
        {
            var sut = CreateSut();
            sut.Capture(MakeMetric("first"));
            sut.Capture(MakeMetric("second"));

            var all = sut.GetAll();
            all[0].DqlQuery.Should().Be("second");
        }

        [Fact]
        public void MetricsUpdated_EventFired_AfterCapture()
        {
            var sut = CreateSut();
            var eventFired = false;
            sut.MetricsUpdated += (s, e) => eventFired = true;

            sut.Capture(MakeMetric());

            eventFired.Should().BeTrue();
        }

        [Fact]
        public void Capture_BeyondMaxCapacity_DropsOlderMetrics()
        {
            var sut = CreateSut();
            // Capture more than 200 metrics
            for (var i = 0; i < 205; i++)
                sut.Capture(MakeMetric($"query {i}"));

            sut.GetAll().Should().HaveCount(200);
            // Latest should still be the last one
            sut.Latest!.DqlQuery.Should().Be("query 204");
        }
    }
}
