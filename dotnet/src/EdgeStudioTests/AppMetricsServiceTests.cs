using EdgeStudio.Shared.Data;
using FluentAssertions;
using System;
using System.IO;
using System.Threading.Tasks;
using Xunit;

namespace EdgeStudioTests
{
    public class AppMetricsServiceTests
    {
        private static AppMetricsService CreateSut() => new();

        // --- IncrementQueryCount + GetSnapshotAsync ---

        [Fact]
        public async Task IncrementQueryCount_CalledThreeTimes_SnapshotHasCount3()
        {
            var sut = CreateSut();
            sut.IncrementQueryCount();
            sut.IncrementQueryCount();
            sut.IncrementQueryCount();

            var snapshot = await sut.GetSnapshotAsync();

            snapshot.TotalQueryCount.Should().Be(3);
        }

        [Fact]
        public async Task IncrementQueryCount_NeverCalled_SnapshotHasCount0()
        {
            var sut = CreateSut();

            var snapshot = await sut.GetSnapshotAsync();

            snapshot.TotalQueryCount.Should().Be(0);
        }

        // --- RecordQueryLatency + GetLatencySamples ---

        [Fact]
        public void RecordQueryLatency_ThreeSamples_GetLatencySamplesHasCount3()
        {
            var sut = CreateSut();
            sut.RecordQueryLatency(10.0);
            sut.RecordQueryLatency(20.0);
            sut.RecordQueryLatency(30.0);

            sut.GetLatencySamples().Should().HaveCount(3);
        }

        [Fact]
        public void RecordQueryLatency_121Samples_GetLatencySamplesHasCount120()
        {
            var sut = CreateSut();
            for (var i = 0; i < 121; i++)
                sut.RecordQueryLatency(i * 1.0);

            sut.GetLatencySamples().Should().HaveCount(120);
        }

        // --- GetSnapshotAsync — query latency aggregation ---

        [Fact]
        public async Task GetSnapshotAsync_TwoSamples_AvgAndLastLatencyCorrect()
        {
            var sut = CreateSut();
            sut.RecordQueryLatency(10.0);
            sut.RecordQueryLatency(30.0);

            var snapshot = await sut.GetSnapshotAsync();

            snapshot.AvgQueryLatencyMs.Should().BeApproximately(20.0, 0.001);
            snapshot.LastQueryLatencyMs.Should().BeApproximately(30.0, 0.001);
        }

        [Fact]
        public async Task GetSnapshotAsync_NoSamples_LastLatencyNullAndAvgFormatted_IsDash()
        {
            var sut = CreateSut();

            var snapshot = await sut.GetSnapshotAsync();

            snapshot.LastQueryLatencyMs.Should().BeNull();
            snapshot.AvgLatencyFormatted.Should().Be("—");
        }

        // --- GetSnapshotAsync — storage categorization ---

        [Fact]
        public async Task GetSnapshotAsync_WithFiles_CategorizesStorageBucketsCorrectly()
        {
            var dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
            try
            {
                // Create directory structure
                Directory.CreateDirectory(Path.Combine(dir, "ditto_store"));
                Directory.CreateDirectory(Path.Combine(dir, "ditto_replication"));
                Directory.CreateDirectory(Path.Combine(dir, "ditto_attachments"));
                Directory.CreateDirectory(Path.Combine(dir, "ditto_auth"));
                Directory.CreateDirectory(Path.Combine(dir, "ditto_logs"));

                // Write files with known sizes
                var storeFile = Path.Combine(dir, "ditto_store", "data.db");
                var replFile = Path.Combine(dir, "ditto_replication", "log.bin");
                var attachFile = Path.Combine(dir, "ditto_attachments", "img.jpg");
                var authFile = Path.Combine(dir, "ditto_auth", "token.bin");
                var walFile = Path.Combine(dir, "checkpoint.wal");
                var shmFile = Path.Combine(dir, "checkpoint.shm");
                var logFile = Path.Combine(dir, "ditto_logs", "app.log");
                var otherFile = Path.Combine(dir, "other.dat");

                await File.WriteAllBytesAsync(storeFile, new byte[100]);
                await File.WriteAllBytesAsync(replFile, new byte[200]);
                await File.WriteAllBytesAsync(attachFile, new byte[300]);
                await File.WriteAllBytesAsync(authFile, new byte[400]);
                await File.WriteAllBytesAsync(walFile, new byte[500]);
                await File.WriteAllBytesAsync(shmFile, new byte[600]);
                await File.WriteAllBytesAsync(logFile, new byte[700]);
                await File.WriteAllBytesAsync(otherFile, new byte[800]);

                var sut = CreateSut();
                var snapshot = await sut.GetSnapshotAsync(dir);

                snapshot.StoreBytes.Should().Be(100);
                snapshot.ReplicationBytes.Should().Be(200);
                snapshot.AttachmentsBytes.Should().Be(300);
                snapshot.AuthBytes.Should().Be(400);
                snapshot.WalShmBytes.Should().Be(1100); // 500 + 600
                snapshot.LogsBytes.Should().Be(700);
                snapshot.OtherBytes.Should().Be(800);
            }
            finally
            {
                if (Directory.Exists(dir))
                    Directory.Delete(dir, recursive: true);
            }
        }

        // --- GetSnapshotAsync — missing directory ---

        [Fact]
        public async Task GetSnapshotAsync_NullDirectory_AllStorageBytesAreZero()
        {
            var sut = CreateSut();

            var snapshot = await sut.GetSnapshotAsync(null);

            snapshot.StoreBytes.Should().Be(0);
            snapshot.ReplicationBytes.Should().Be(0);
            snapshot.AttachmentsBytes.Should().Be(0);
            snapshot.AuthBytes.Should().Be(0);
            snapshot.WalShmBytes.Should().Be(0);
            snapshot.LogsBytes.Should().Be(0);
            snapshot.OtherBytes.Should().Be(0);
        }

        [Fact]
        public async Task GetSnapshotAsync_NonExistentDirectory_AllStorageBytesAreZero()
        {
            var sut = CreateSut();
            var nonExistent = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());

            var snapshot = await sut.GetSnapshotAsync(nonExistent);

            snapshot.StoreBytes.Should().Be(0);
            snapshot.ReplicationBytes.Should().Be(0);
            snapshot.AttachmentsBytes.Should().Be(0);
            snapshot.AuthBytes.Should().Be(0);
            snapshot.WalShmBytes.Should().Be(0);
            snapshot.LogsBytes.Should().Be(0);
            snapshot.OtherBytes.Should().Be(0);
        }

        // --- GetSnapshotAsync — process metrics present ---

        [Fact]
        public async Task GetSnapshotAsync_ResidentMemoryBytesGreaterThanZero()
        {
            var sut = CreateSut();

            var snapshot = await sut.GetSnapshotAsync();

            snapshot.ResidentMemoryBytes.Should().BeGreaterThan(0);
        }

        [Fact]
        public async Task GetSnapshotAsync_ProcessUptimeIsNonNegative()
        {
            var sut = CreateSut();

            var snapshot = await sut.GetSnapshotAsync();

            snapshot.ProcessUptime.Should().BeGreaterThanOrEqualTo(TimeSpan.Zero);
        }
    }
}
