using EdgeStudio.Shared.Models;
using FluentAssertions;
using System;
using Xunit;

namespace EdgeStudioTests
{
    public class AppMetricsSnapshotTests
    {
        private static AppMetricsSnapshot MakeSnapshot(
            long residentBytes = 0, long virtualBytes = 0, double cpuSecs = 0,
            int handles = 0, TimeSpan? uptime = null,
            int queryCount = 0, double avgLatency = 0, double? lastLatency = null,
            long storeBytes = 0, long replBytes = 0, long attachBytes = 0,
            long authBytes = 0, long walBytes = 0, long logBytes = 0, long otherBytes = 0) =>
            new AppMetricsSnapshot(
                DateTimeOffset.UtcNow, residentBytes, virtualBytes, cpuSecs, handles,
                uptime ?? TimeSpan.Zero, queryCount, avgLatency, lastLatency,
                storeBytes, replBytes, attachBytes, authBytes, walBytes, logBytes, otherBytes,
                Array.Empty<CollectionStorageInfo>());

        // --- FormatBytes via ResidentMemoryFormatted ---

        [Fact]
        public void ResidentMemoryFormatted_Zero_Returns0B()
        {
            var sut = MakeSnapshot(residentBytes: 0);
            sut.ResidentMemoryFormatted.Should().Be("0 B");
        }

        [Fact]
        public void ResidentMemoryFormatted_512Bytes_Returns512B()
        {
            var sut = MakeSnapshot(residentBytes: 512);
            sut.ResidentMemoryFormatted.Should().Be("512 B");
        }

        [Fact]
        public void ResidentMemoryFormatted_1024Bytes_Returns1_0KB()
        {
            var sut = MakeSnapshot(residentBytes: 1024);
            sut.ResidentMemoryFormatted.Should().Be("1.0 KB");
        }

        [Fact]
        public void ResidentMemoryFormatted_1536Bytes_Returns1_5KB()
        {
            var sut = MakeSnapshot(residentBytes: 1536);
            sut.ResidentMemoryFormatted.Should().Be("1.5 KB");
        }

        [Fact]
        public void ResidentMemoryFormatted_1MB_Returns1_0MB()
        {
            var sut = MakeSnapshot(residentBytes: 1048576);
            sut.ResidentMemoryFormatted.Should().Be("1.0 MB");
        }

        [Fact]
        public void ResidentMemoryFormatted_1_5MB_Returns1_5MB()
        {
            var sut = MakeSnapshot(residentBytes: 1572864);
            sut.ResidentMemoryFormatted.Should().Be("1.5 MB");
        }

        // --- FormatBytes via StoreBytesFormatted ---

        [Fact]
        public void StoreBytesFormatted_Zero_Returns0B()
        {
            var sut = MakeSnapshot(storeBytes: 0);
            sut.StoreBytesFormatted.Should().Be("0 B");
        }

        [Fact]
        public void StoreBytesFormatted_1024Bytes_Returns1_0KB()
        {
            var sut = MakeSnapshot(storeBytes: 1024);
            sut.StoreBytesFormatted.Should().Be("1.0 KB");
        }

        // --- UptimeFormatted ---

        [Fact]
        public void UptimeFormatted_30Seconds_Returns30s()
        {
            var sut = MakeSnapshot(uptime: TimeSpan.FromSeconds(30));
            sut.UptimeFormatted.Should().Be("30s");
        }

        [Fact]
        public void UptimeFormatted_90Seconds_Returns1m30s()
        {
            var sut = MakeSnapshot(uptime: TimeSpan.FromSeconds(90));
            sut.UptimeFormatted.Should().Be("1m 30s");
        }

        [Fact]
        public void UptimeFormatted_65Minutes_Returns1h5m()
        {
            var sut = MakeSnapshot(uptime: TimeSpan.FromMinutes(65));
            sut.UptimeFormatted.Should().Be("1h 5m");
        }

        [Fact]
        public void UptimeFormatted_1Day2Hours_Returns1d2h()
        {
            var sut = MakeSnapshot(uptime: TimeSpan.FromHours(26));
            sut.UptimeFormatted.Should().Be("1d 2h");
        }

        // --- AvgLatencyFormatted ---

        [Fact]
        public void AvgLatencyFormatted_QueryCountZero_ReturnsDash()
        {
            var sut = MakeSnapshot(queryCount: 0, avgLatency: 100.0);
            sut.AvgLatencyFormatted.Should().Be("—");
        }

        [Fact]
        public void AvgLatencyFormatted_QueryCountPositive_SubMs_ReturnsLessThan1ms()
        {
            var sut = MakeSnapshot(queryCount: 1, avgLatency: 0.5);
            sut.AvgLatencyFormatted.Should().Be("< 1 ms");
        }

        [Fact]
        public void AvgLatencyFormatted_QueryCountPositive_42_5ms_Returns42_5ms()
        {
            var sut = MakeSnapshot(queryCount: 5, avgLatency: 42.5);
            sut.AvgLatencyFormatted.Should().Be("42.5 ms");
        }

        [Fact]
        public void AvgLatencyFormatted_QueryCountPositive_1500ms_Returns1_50s()
        {
            var sut = MakeSnapshot(queryCount: 3, avgLatency: 1500.0);
            sut.AvgLatencyFormatted.Should().Be("1.50 s");
        }

        // --- LastLatencyFormatted ---

        [Fact]
        public void LastLatencyFormatted_Null_ReturnsDash()
        {
            var sut = MakeSnapshot(lastLatency: null);
            sut.LastLatencyFormatted.Should().Be("—");
        }

        [Fact]
        public void LastLatencyFormatted_SubMs_ReturnsLessThan1ms()
        {
            var sut = MakeSnapshot(lastLatency: 0.5);
            sut.LastLatencyFormatted.Should().Be("< 1 ms");
        }

        [Fact]
        public void LastLatencyFormatted_42_5ms_Returns42_5ms()
        {
            var sut = MakeSnapshot(lastLatency: 42.5);
            sut.LastLatencyFormatted.Should().Be("42.5 ms");
        }

        // --- TotalStorageBytes ---

        [Fact]
        public void TotalStorageBytes_SumsAllStorageFields()
        {
            var sut = MakeSnapshot(
                storeBytes: 100, replBytes: 200, attachBytes: 300,
                authBytes: 400, walBytes: 500, logBytes: 600, otherBytes: 700);
            sut.TotalStorageBytes.Should().Be(2800);
        }

        [Fact]
        public void TotalStorageBytes_AllZero_ReturnsZero()
        {
            var sut = MakeSnapshot();
            sut.TotalStorageBytes.Should().Be(0);
        }

        // --- CollectionStorageInfo ---

        [Fact]
        public void CollectionStorageInfo_EstimatedBytesFormatted_Zero_Returns0B()
        {
            var info = new CollectionStorageInfo("myCollection", 5, 0);
            info.EstimatedBytesFormatted.Should().Be("0 B");
        }

        [Fact]
        public void CollectionStorageInfo_EstimatedBytesFormatted_2048_Returns2_0KB()
        {
            var info = new CollectionStorageInfo("myCollection", 5, 2048);
            info.EstimatedBytesFormatted.Should().Be("2.0 KB");
        }

        [Fact]
        public void CollectionStorageInfo_DocumentCountFormatted_Returns5docs()
        {
            var info = new CollectionStorageInfo("myCollection", 5, 0);
            info.DocumentCountFormatted.Should().Be("5 docs");
        }
    }
}
