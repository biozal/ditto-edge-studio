using EdgeStudio.Shared.Models;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
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

    public async Task<AppMetricsSnapshot> GetSnapshotAsync(string? persistenceDirectory = null, DittoSDK.Ditto? ditto = null, CancellationToken ct = default)
    {
        // Gather process and query metrics synchronously (instant)
        var proc = Process.GetCurrentProcess();
        proc.Refresh();
        var residentMemory = proc.WorkingSet64;
        var virtualMemory = proc.VirtualMemorySize64;
        var cpuTime = proc.TotalProcessorTime.TotalSeconds;
        var handleCount = proc.HandleCount;
        var uptime = DateTimeOffset.UtcNow - _startTime;

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

        // Run storage scan and collection breakdown in parallel on thread pool
        var storageTask = Task.Run(() => ComputeStorageMetrics(persistenceDirectory, ct), ct);
        var collectionTask = ditto != null
            ? ComputeCollectionBreakdownAsync(ditto, ct)
            : Task.FromResult<IReadOnlyList<CollectionStorageInfo>>(Array.Empty<CollectionStorageInfo>());

        await Task.WhenAll(storageTask, collectionTask);

        var storage = storageTask.Result;
        var collectionBreakdown = collectionTask.Result;

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
            StoreBytes: storage.Store,
            ReplicationBytes: storage.Replication,
            AttachmentsBytes: storage.Attachments,
            AuthBytes: storage.Auth,
            WalShmBytes: storage.WalShm,
            LogsBytes: storage.Logs,
            OtherBytes: storage.Other,
            CollectionBreakdown: collectionBreakdown
        );
    }

    private record StorageMetrics(long Store, long Replication, long Attachments, long Auth, long WalShm, long Logs, long Other);

    private static StorageMetrics ComputeStorageMetrics(string? persistenceDirectory, CancellationToken ct)
    {
        long storeBytes = 0, replicationBytes = 0, attachmentsBytes = 0,
             authBytes = 0, walShmBytes = 0, logsBytes = 0, otherBytes = 0;

        if (string.IsNullOrEmpty(persistenceDirectory) || !Directory.Exists(persistenceDirectory))
            return new StorageMetrics(0, 0, 0, 0, 0, 0, 0);

        try
        {
            foreach (var file in Directory.EnumerateFiles(persistenceDirectory, "*", SearchOption.AllDirectories))
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

        return new StorageMetrics(storeBytes, replicationBytes, attachmentsBytes, authBytes, walShmBytes, logsBytes, otherBytes);
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

            // Query all collections in parallel to calculate size
            var tasks = collections.Select(async collectionName =>
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
                            totalBytes += System.Text.Json.JsonSerializer.SerializeToUtf8Bytes(item.Value).LongLength;
                            docCount++;
                        }
                        finally
                        {
                            item.Dematerialize();
                        }
                    }
                    docResult.Dispose();

                    return new CollectionStorageInfo(collectionName, docCount, totalBytes);
                }
                catch { return new CollectionStorageInfo(collectionName, 0, 0); }
            }).ToList();

            var results = await Task.WhenAll(tasks);
            var breakdown = results.OrderByDescending(c => c.EstimatedBytes).ToList();
            return breakdown.AsReadOnly();
        }
        catch (OperationCanceledException) { throw; }
        catch { return Array.Empty<CollectionStorageInfo>(); }
    }
}
