using EdgeStudio.Shared.Models;
using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;

namespace EdgeStudio.Shared.Data.Repositories
{
    public interface IHistoryRepository
        : ICloseDatabase, IDisposable
    {
        Task AddQueryHistory(QueryHistory queryHistory);
        Task DeleteQueryHistory(QueryHistory queryHistory);
        void RegisterObserver(ObservableCollection<QueryHistory> queryHistorys, Action<string> errorMessage);
    }
}
