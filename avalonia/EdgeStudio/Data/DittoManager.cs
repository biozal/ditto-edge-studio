using System;
using System.IO;
using System.Threading.Tasks;
using DittoSDK;
using EdgeStudio.Models;

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
                DittoSelectedApp.Dispose();
                DittoSelectedApp = null;
            }
        }

        public Ditto GetLocalDitto()
        {
            if (DittoLocal is null)
            {
                throw new InvalidOperationException("DittoManager is not properly initialized.");
            }
            return DittoLocal;
        }

        public Ditto GetSelectedAppDitto()
        {
            if (DittoSelectedApp is null)
            {
                throw new InvalidOperationException("DittoManager is not properly initialized.");
            }
            return DittoSelectedApp;
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

                    //create indexes
                    await DittoLocal.Store.ExecuteAsync("CREATE INDEX IF NOT EXISTS idx_dittoSubscriptions_selectedApp_id ON dittosubscriptions(selectedApp_id)");

                }
                else
                {
                    throw new InvalidOperationException("Failed to open Ditto instance.");
                }
            }
            else
            {
                throw new InvalidOperationException("Ditto store is already initialized.");
            }

        }

        public async Task<bool> InitializeDittoSelectedApp(DittoDatabaseConfig dittoDatabaseConfig) 
        {
            var isSuccess = false;
            CloseSelectedApp();

            this.SelectedDatabaseConfig = dittoDatabaseConfig;
            var dbName = $"{dittoDatabaseConfig.Name.Trim().ToLower()}-{dittoDatabaseConfig.DatabaseId}";

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
                        await ditto.Auth.LoginAsync(dittoDatabaseConfig.AuthToken, 
                            DittoAuthenticationProvider.Development);
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
                throw new InvalidOperationException("DittoSelectedApp is not initialized.");
            }
            this.DittoSelectedApp.Sync.Start(); 
        }

        public void SelectedAppStopSync()
        {
            if (this.DittoSelectedApp == null)
            {
                throw new InvalidOperationException("DittoSelectedApp is not initialized.");
            }
            this.DittoSelectedApp.Sync.Stop();
        }
    }
}