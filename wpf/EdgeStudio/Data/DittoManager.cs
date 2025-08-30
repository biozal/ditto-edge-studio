using DittoSDK;
using EdgeStudio.Models;
using System.IO;

namespace EdgeStudio.Data
{
    public class DittoManager
    {
        private bool _isStoreInitialized = false;

        public Ditto? DittoLocal { get; set; } = null;
        public Ditto? DittoSelectedApp { get; set; } = null;

        public DittoDatabaseConfig? SelectedDatabaseConfig { get; set; } = null;

        public async Task InitializeDittoAsync(DittoDatabaseConfig databaseConfig)
        {
            if (!_isStoreInitialized)
            {
                SelectedDatabaseConfig = databaseConfig;
                //calculate the directory to save the local cache database in
                string appDataPath = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
                string persistenceDirectory = Path.Combine(appDataPath, "DittoEdgeStudio", "dittolocalcache");

                // Ensure the directory exists
                Directory.CreateDirectory(persistenceDirectory);

                var config = new DittoConfig(databaseConfig.DatabaseId,
                    connect: new DittoConfigConnect.Server(new Uri(databaseConfig.AuthUrl)),
                    persistenceDirectory: persistenceDirectory 
                 );

                DittoLocal = await Ditto.OpenAsync(config);
                if (DittoLocal != null)
                {
                    // Set up authentication expiration handler (required for server connections)
                    DittoLocal.Auth.ExpirationHandler = async (ditto, secondsRemaining) =>
                    {
                        try
                        {
                            await ditto.Auth.LoginAsync(databaseConfig.AuthToken, "server");
                            _isStoreInitialized = true;
                        }
                        catch (Exception error)
                        {
                            throw new InvalidOperationException("Ditto authentication failed.", error);
                        }
                    };

                    //Required for DQL to work
                    DittoLocal.DisableSyncWithV3();

                    //disable strict mode to allow for more flexible queries
                    await DittoLocal.Store.ExecuteAsync("ALTER SYSTEM SET DQL_STRICT_MODE = false");

                } else
                {
                    throw new InvalidOperationException("Failed to open Ditto instance.");
                }
            } 
            else 
            {
                throw new InvalidStateException("Ditto store is already initialized.");
            }
        }
    }
}
