using System;
using System.Collections.Generic;
using EdgeStudio.Shared.Models;

namespace EdgeStudio.Shared.Data
{
    public interface IQueryMetricsService
    {
        void Capture(QueryMetric metric);
        QueryMetric? Latest { get; }
        IReadOnlyList<QueryMetric> GetAll();
        event EventHandler MetricsUpdated;
    }
}
