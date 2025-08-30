using DittoSDK;
using EdgeStudio.Models;
using System.IO;

namespace EdgeStudio.Data
{
    public class DittoManager : IDittoManager
    {
        private bool _isStoreInitialized = false;

        public Ditto? DittoLocal { get; set; } = null;
        public Ditto? DittoSelectedApp { get; set; } = null;

        public DittoDatabaseConfig? SelectedDatabaseConfig { get; set; } = null;

        public void CloseSelectedApp()
        {
            if (DittoSelectedApp != null)
            {
                DittoSelectedApp.Sync.Stop();
                DittoSelectedApp = null;
            }
        }

        public Ditto GetLocalDitto()
        {
            if (DittoLocal is null)
            {
                throw new InvalidStateException("DittoManager is not properly initialized.");
            }
            return DittoLocal;
        }

        public async Task InitializeDittoAsync(DittoDatabaseConfig databaseConfig)
        {
            if (!_isStoreInitialized)
            {
                SelectedDatabaseConfig = databaseConfig;
                //calculate the directory to save the local cache database in
                var appDataPath = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
                var persistenceDirectory = Path.Combine(appDataPath, "DittoEdgeStudio", "dittolocalcache");

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

                }
                else
                {
                    throw new InvalidOperationException("Failed to open Ditto instance.");
                }
            }
            else
            {
                throw new InvalidStateException("Ditto store is already initialized.");
            }

        }

        public async Task<bool> InitializeDittoSelectedApp(DittoDatabaseConfig dittoDatabaseConfig) 
        {
            var isSuccess = false;
            CloseSelectedApp();

            this.SelectedDatabaseConfig = dittoDatabaseConfig;
            var dbName = $"{dittoDatabaseConfig.Name.Trim().ToLower()}-{System.Guid.NewGuid().ToString()}";

            //calculate the directory to save the local cache database in
            var appDataPath = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            var persistenceDirectory = Path.Combine(appDataPath, "DittoEdgeStudio", dbName);

            // Ensure the directory exists
            Directory.CreateDirectory(persistenceDirectory);
            var config = new DittoConfig(dittoDatabaseConfig.DatabaseId,
                connect: new DittoConfigConnect.Server(new Uri(dittoDatabaseConfig.AuthUrl)),
                persistenceDirectory: persistenceDirectory
            );

            this.DittoSelectedApp = await Ditto.OpenAsync(config);
            if (this.DittoSelectedApp != null)
            {
                // Set up authentication expiration handler (required for server connections)
                this.DittoSelectedApp.Auth.ExpirationHandler = async (ditto, secondsRemaining) =>
                {
                    try
                    {
                        await ditto.Auth.LoginAsync(dittoDatabaseConfig.AuthToken, "server");
                        _isStoreInitialized = true;
                    }
                    catch (Exception error)
                    {
                        throw new InvalidOperationException("Ditto authentication failed.", error);
                    }
                };

                //Required for DQL to work
                this.DittoSelectedApp.DisableSyncWithV3();

                //disable strict mode to allow for more flexible queries
                await this.DittoSelectedApp.Store.ExecuteAsync("ALTER SYSTEM SET DQL_STRICT_MODE = false");
                isSuccess = true;
            }
            else
            {
                throw new InvalidOperationException("Failed to open Ditto instance.");
            }
            return isSuccess;
        }

        public void SelectedAppStartSync()
        {
            if (this.DittoSelectedApp == null)
            {
                throw new InvalidStateException("DittoSelectedApp is not initialized.");
            }
            this.DittoSelectedApp.Sync.Start(); 
        }

        public void SelectedAppStopSync()
        {
            if (this.DittoSelectedApp == null)
            {
                throw new InvalidStateException("DittoSelectedApp is not initialized.");
            }
            this.DittoSelectedApp.Sync.Stop();
        }
    }
}
