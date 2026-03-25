using System.Threading.Tasks;
using DittoSDK;
using EdgeStudio.Shared.Models;

namespace EdgeStudio.Shared.Data
{
    public interface IDittoManager : ICloseDatabase
    {
        Ditto? DittoSelectedApp { get; set; }
        DittoDatabaseConfig? SelectedDatabaseConfig { get; set; }

        Ditto GetSelectedAppDitto();
        Task<bool> InitializeDittoSelectedApp(DittoDatabaseConfig databaseConfig);
        void SelectedAppStartSync();
        void SelectedAppStopSync();
        Task ApplyTransportConfigurationAsync(
            bool bluetoothEnabled,
            bool lanEnabled,
            bool awdlEnabled,
            bool wifiAwareEnabled,
            bool webSocketEnabled);

        string? GetPersistenceDirectory();
    }
}
