using System.Threading.Tasks;
using DittoSDK;
using EdgeStudio.Models;

namespace EdgeStudio.Data
{
    public interface IDittoManager
    {
        Ditto? DittoLocal { get; set; }
        Ditto? DittoSelectedApp { get; set; }
        DittoDatabaseConfig? SelectedDatabaseConfig { get; set; }
        
        void CloseSelectedApp();
        Ditto GetLocalDitto();
        Ditto GetSelectedAppDitto();
        Task InitializeDittoAsync(DittoDatabaseConfig databaseConfig);
        Task<bool> InitializeDittoSelectedApp(DittoDatabaseConfig databaseConfig);
        void SelectedAppStartSync();
        void SelectedAppStopSync();

    }
}