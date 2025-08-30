using DittoSDK;
using EdgeStudio.Models;

namespace EdgeStudio.Data
{
    public interface IDittoManager
    {
        Ditto? DittoLocal { get; set; }
        Ditto? DittoSelectedApp { get; set; }
        DittoDatabaseConfig? SelectedDatabaseConfig { get; set; }
        
        Task InitializeDittoAsync(DittoDatabaseConfig databaseConfig);
    }
}