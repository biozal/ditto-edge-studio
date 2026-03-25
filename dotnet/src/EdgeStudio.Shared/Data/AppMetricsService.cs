using EdgeStudio.Shared.Models;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace EdgeStudio.Shared.Data;

public class AppMetricsService : IAppMetricsService
{
    private readonly DateTimeOffset _startTime = DateTimeOffset.UtcNow;
    private int _queryCount = 0;
    // Ring buffer of last 120 latency samples
    private readonly Queue<double> _latencySamples = new();
    private const int MaxSamples = 120;
    private readonly object _lock = new();

    public void IncrementQueryCount() => Interlocked.Increment(ref _queryCount);

    public void RecordQueryLatency(double latencyMs)
    {
        lock (_lock)
        {
            _latencySamples.Enqueue(latencyMs);
            while (_latencySamples.Count > MaxSamples)
                _latencySamples.Dequeue();
        }
    }

    public IReadOnlyList<double> GetLatencySamples()
    {
        lock (_lock)
            return _latencySamples.ToList().AsReadOnly();
    }

    public Task<AppMetricsSnapshot> GetSnapshotAsync(string? persistenceDirectory = null, DittoSDK.Ditto? ditto = null, CancellationToken ct = default)
    {
        return Task.Run(async () =>
        {
            // Process metrics
            var proc = Process.GetCurrentProcess();
            proc.Refresh();
            var residentMemory = proc.WorkingSet64;
            var virtualMemory = proc.VirtualMemorySize64;
            var cpuTime = proc.TotalProcessorTime.TotalSeconds;
            var handleCount = proc.HandleCount;
            var uptime = DateTimeOffset.UtcNow - _startTime;

            // Query metrics
            double avgLatency = 0;
            double? lastLatency = null;
            int totalCount = _queryCount;
            List<double> samples;
            lock (_lock)
            {
                samples = _latencySamples.ToList();
            }
            if (samples.Count > 0)
            {
                avgLatency = samples.Average();
                lastLatency = samples[^1];
            }

            // Storage metrics
            long storeBytes = 0, replicationBytes = 0, attachmentsBytes = 0,
                 authBytes = 0, walShmBytes = 0, logsBytes = 0, otherBytes = 0;

            if (!string.IsNullOrEmpty(persistenceDirectory) && Directory.Exists(persistenceDirectory))
            {
                try
                {
                    var allFiles = Directory.GetFiles(persistenceDirectory, "*", SearchOption.AllDirectories);
                    foreach (var file in allFiles)
                    {
                        ct.ThrowIfCancellationRequested();
                        try
                        {
                            var info = new FileInfo(file);
                            var size = info.Length;
                            var rel = file.Substring(persistenceDirectory.Length)
                                         .Replace('\\', '/').TrimStart('/');

                            if (rel.Contains("ditto_store"))             storeBytes += size;
                            else if (rel.Contains("ditto_replication"))  replicationBytes += size;
                            else if (rel.Contains("ditto_attachments"))  attachmentsBytes += size;
                            else if (rel.Contains("ditto_auth"))         authBytes += size;
                            else if (rel.EndsWith(".wal") || rel.EndsWith(".shm")) walShmBytes += size;
                            else if (rel.Contains("ditto_logs"))         logsBytes += size;
                            else                                          otherBytes += size;
                        }
                        catch { /* skip inaccessible files */ }
                    }
                }
                catch (OperationCanceledException) { throw; }
                catch { /* skip if directory not accessible */ }
            }

            var collectionBreakdown = ditto != null
                ? await ComputeCollectionBreakdownAsync(ditto, ct)
                : (IReadOnlyList<CollectionStorageInfo>)Array.Empty<CollectionStorageInfo>();

            return new AppMetricsSnapshot(
                CapturedAt: DateTimeOffset.UtcNow,
                ResidentMemoryBytes: residentMemory,
                VirtualMemoryBytes: virtualMemory,
                CpuTimeSeconds: cpuTime,
                OpenHandleCount: handleCount,
                ProcessUptime: uptime,
                TotalQueryCount: totalCount,
                AvgQueryLatencyMs: avgLatency,
                LastQueryLatencyMs: lastLatency,
                StoreBytes: storeBytes,
                ReplicationBytes: replicationBytes,
                AttachmentsBytes: attachmentsBytes,
                AuthBytes: authBytes,
                WalShmBytes: walShmBytes,
                LogsBytes: logsBytes,
                OtherBytes: otherBytes,
                CollectionBreakdown: collectionBreakdown
            );
        }, ct);
    }

    private static async Task<IReadOnlyList<CollectionStorageInfo>> ComputeCollectionBreakdownAsync(
        DittoSDK.Ditto ditto, CancellationToken ct)
    {
        try
        {
            var collections = new List<string>();

            // Get all collection names
            var colResult = await ditto.Store.ExecuteAsync("SELECT * FROM system:collections");
            foreach (var item in colResult.Items)
            {
                try
                {
                    var name = item.Value["name"]?.ToString();
                    if (!string.IsNullOrEmpty(name))
                        collections.Add(name);
                }
                finally
                {
                    item.Dematerialize();
                }
            }
            colResult.Dispose();

            var breakdown = new List<CollectionStorageInfo>();

            foreach (var collectionName in collections)
            {
                ct.ThrowIfCancellationRequested();

                try
                {
                    var escaped = collectionName.Replace("`", "``");
                    var docResult = await ditto.Store.ExecuteAsync($"SELECT * FROM `{escaped}`");
                    long totalBytes = 0;
                    int docCount = 0;

                    foreach (var item in docResult.Items)
                    {
                        try
                        {
                            totalBytes += JsonSerializer.SerializeToUtf8Bytes(item.Value).LongLength;
                            docCount++;
                        }
                        finally
                        {
                            item.Dematerialize();
                        }
                    }
                    docResult.Dispose();

                    breakdown.Add(new CollectionStorageInfo(collectionName, docCount, totalBytes));
                }
                catch { /* skip inaccessible collections */ }
            }

            breakdown.Sort((a, b) => b.EstimatedBytes.CompareTo(a.EstimatedBytes));
            return breakdown.AsReadOnly();
        }
        catch (OperationCanceledException) { throw; }
        catch { return Array.Empty<CollectionStorageInfo>(); }
    }
}
