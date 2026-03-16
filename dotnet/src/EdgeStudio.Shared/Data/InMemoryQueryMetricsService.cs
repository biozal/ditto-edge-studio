using System;
using System.Collections.Generic;
using EdgeStudio.Shared.Models;

namespace EdgeStudio.Shared.Data
{
    /// <summary>
    /// In-memory store for query performance metrics. Capped at 200 entries (newest first).
    /// </summary>
    public class InMemoryQueryMetricsService : IQueryMetricsService
    {
        private const int MaxCapacity = 200;
        private readonly List<QueryMetric> _metrics = new();
        private readonly object _lock = new();

        public QueryMetric? Latest { get; private set; }

        public event EventHandler? MetricsUpdated;

        public void Capture(QueryMetric metric)
        {
            lock (_lock)
            {
                _metrics.Insert(0, metric);
                if (_metrics.Count > MaxCapacity)
                    _metrics.RemoveAt(_metrics.Count - 1);
                Latest = metric;
            }
            MetricsUpdated?.Invoke(this, EventArgs.Empty);
        }

        public IReadOnlyList<QueryMetric> GetAll()
        {
            lock (_lock)
                return _metrics.AsReadOnly();
        }
    }
}
