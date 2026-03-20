using EdgeStudio.Shared.Models;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace EdgeStudio.Shared.Data;

public interface IAppMetricsService
{
    Task<AppMetricsSnapshot> GetSnapshotAsync(string? persistenceDirectory = null, DittoSDK.Ditto? ditto = null, CancellationToken ct = default);
    void RecordQueryLatency(double latencyMs);
    void IncrementQueryCount();
    IReadOnlyList<double> GetLatencySamples();
}
