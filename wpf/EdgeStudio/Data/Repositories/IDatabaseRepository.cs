using EdgeStudio.Models;
using System.Collections.ObjectModel;

namespace EdgeStudio.Data.Repositories
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
