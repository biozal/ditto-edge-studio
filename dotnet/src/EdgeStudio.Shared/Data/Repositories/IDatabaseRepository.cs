using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using EdgeStudio.Shared.Models;

namespace EdgeStudio.Shared.Data.Repositories
{
    public interface IDatabaseRepository
    {
        Task AddDittoDatabaseConfig(DittoDatabaseConfig config);
        Task DeleteDittoDatabaseConfig(DittoDatabaseConfig config);
        Task UpdateDatabaseConfig(DittoDatabaseConfig config);

        void RegisterLocalObservers(ObservableCollection<DittoDatabaseConfig> databaseConfigs, Action<string> errorMessage);
        Task SetupDatabaseConfigSubscriptions();
    }
}
