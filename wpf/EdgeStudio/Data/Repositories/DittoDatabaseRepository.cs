using DittoSDK;
using EdgeStudio.Models;
using System.Collections.ObjectModel;
using System.Windows;

namespace EdgeStudio.Data.Repositories
{
    public class DittoDatabaseRepository(DittoManager _dittoManager)
        : IDatabaseRepository, IDisposable
    {
        private DittoSyncSubscription? _localAppConfigSubscription;
        private DittoStoreObserver? _localDittoStoreObserver;
        private bool disposedValue;
        private List<string?> _previousDocumentIds = new List<string?>(); // Store only extracted IDs

        public async Task AddDittoDatabaseConfig(DittoDatabaseConfig config)
        {
            var ditto = GetDitto();
            var query = "INSERT INTO dittodatabaseconfigs INITIAL DOCUMENTS (:newConfig)";
            var args = new Dictionary<string, object>
            {
                { "newConfig", new Dictionary<string, object>
                    {
                        { "_id", config.Id },
                        { "name", config.Name },
                        { "appId", config.DatabaseId },
                        { "authToken", config.AuthToken },
                        { "authUrl", config.AuthUrl },
                        { "websocketUrl", config.WebsocketUrl },
                        { "httpApiUrl", config.HttpApiUrl },
                        { "httpApiKey", config.HttpApiKey },
                        { "mode", config.Mode },
                        { "allowUntrustedCerts", config.AllowUntrustedCerts }
                    }
                }
            };
            await ditto.Store.ExecuteAsync(query, args);
        }

        public async Task DeleteDittoDatabaseConfig(DittoDatabaseConfig config)
        {
            var ditto = GetDitto();
            await ditto.Store.ExecuteAsync("DELETE FROM dittodatabaseconfigs WHERE _id = :id",
                new Dictionary<string, object> { { "id", config.Id } });
        }

        public void RegisterLocalObservers(ObservableCollection<DittoDatabaseConfig> databaseConfigs, Action<string> errorMessage)
        {
            var differ = new DittoDiffer();

            var ditto = GetDitto();
            _localDittoStoreObserver = ditto.Store.RegisterObserver("SELECT * FROM dittodatabaseconfigs ORDER BY name", (result) =>
            {
                var diff = differ.Diff(result.Items);
                // Extract current document IDs and dematerialize items
                var currentDocumentIds = result.Items?.Select(item =>
                {
                    var id = item.Value.TryGetValue("_id", out var idObj) ? idObj?.ToString() : "";
                    item.Dematerialize(); // Release memory after extracting data
                    return id;
                }).ToList() ?? new();

                // Handle deletions using stored IDs from previous emission
                foreach (var index in diff.Deletions)
                {
                    if (index < _previousDocumentIds.Count)
                    {
                        var deletedId = _previousDocumentIds[index];
                        if (deletedId != null)
                        {
                            //make sure to do the update on the Main UI Thread
                            Application.Current.Dispatcher.Invoke(() =>
                            {
                                databaseConfigs.Remove(databaseConfigs.First(dc => dc.Id == deletedId));
                            });
                        }
                    }
                }

                // Handle insertions using current IDs
                foreach (var index in diff.Insertions)
                {
                    DittoDatabaseConfig newConfig = GetDitoDatabaseConfigFromQueryResult(result, index);
                    //make sure to do the update on the Main UI Thread
                   Application.Current.Dispatcher.Invoke(() => {
                        databaseConfigs.Add(newConfig);
                   });
                }

                // Handle updates using current IDs
                foreach (var index in diff.Updates)
                {
                    var updatedId = currentDocumentIds[index];
                    if (updatedId != null)
                    {
                        DittoDatabaseConfig newConfig = GetDitoDatabaseConfigFromQueryResult(result, index);
                        var updateIndex = databaseConfigs.IndexOf(databaseConfigs.First(dc => dc.Id == updatedId));
                        Application.Current.Dispatcher.Invoke(() => {
                            databaseConfigs[updateIndex] = newConfig;
                        });
                    }
                }

                // Store only the document IDs for next callback - no live references!
                _previousDocumentIds = currentDocumentIds; 

                // Close the query result to free resources
                try
                {
                    result.Dispose();
                }
                catch (Exception e)
                {
                    // Handle any closing errors
                    errorMessage($"{e.Message}, Stack Trace: {e.StackTrace}");
                }
            });
        }
       
        public async Task SetupDatabaseConfigSubscriptions()
        {
            var ditto = GetDitto();
            // Set sync scopes for collections to local peer only so they don't sync
            // by accident
            var syncScopes = new Dictionary<string, string> {
                { "dittodatabaseconfigs", "LocalPeerOnly" },
                { "dittosubscriptions", "LocalPeerOnly"},
                { "dittoobservations", "LocalPeerOnly" },
                { "dittoqueryfavorites", "LocalPeerOnly" },
                { "dittoqueryhistory", "LocalPeerOnly" },
            };
            var args = new Dictionary<string, object>
            {
                { "syncScopes", syncScopes }
            };

            await ditto.Store.ExecuteAsync("ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES = :syncScopes", args);
            _localAppConfigSubscription = ditto.Sync.RegisterSubscription("SELECT * FROM dittodatabaseconfigs");
            ditto.Sync.Start();
        }

        public async Task UpdateDatabaseConfig(DittoDatabaseConfig config)
        {
            var ditto = GetDitto();
            var query = "UPDATE dittodatabaseconfigs SET name = :name, appId = :appId, authToken = :authToken, authUrl = :authUrl, websocketUrl = :websocketUrl, httpApiUrl = :httpApiUrl, httpApiKey = :httpApiKey, mode = :mode, allowUntrustedCerts = :allowUntrustedCerts WHERE _id = :_id";
            var args = new Dictionary<string, object>
            {
                { "_id", config.Id },
                { "name", config.Name },
                { "appId", config.DatabaseId },
                { "authToken", config.AuthToken },
                { "authUrl", config.AuthUrl },
                { "websocketUrl", config.WebsocketUrl },
                { "httpApiUrl", config.HttpApiUrl },
                { "httpApiKey", config.HttpApiKey },
                { "mode", config.Mode },
                { "allowUntrustedCerts", config.AllowUntrustedCerts }
            };
            await ditto.Store.ExecuteAsync(query, args);
        }

        protected virtual void Dispose(bool disposing)
        {
            if (!disposedValue)
            {
                if (disposing)
                {
                    _localAppConfigSubscription?.Cancel();
                    _localAppConfigSubscription = null;

                    _localDittoStoreObserver?.Cancel();
                    _localDittoStoreObserver = null;
                }

                disposedValue = true;
            }
        }

        public void Dispose()
        {
            // Do not change this code. Put cleanup code in 'Dispose(bool disposing)' method
            Dispose(disposing: true);
            GC.SuppressFinalize(this);
        }

        private Ditto GetDitto()
        {
            if (_dittoManager.DittoLocal is null)
            {
                throw new InvalidStateException("DittoManager is not properly initialized.");
            }
            return _dittoManager.DittoLocal;
        }

        private static DittoDatabaseConfig GetDitoDatabaseConfigFromQueryResult(DittoQueryResult result, int index)
        {
            var newItem = result.Items[index];
            var valueDict = newItem.Value;

            valueDict.TryGetValue("_id", out object? idObj);
            valueDict.TryGetValue("name", out object? nameObj);
            valueDict.TryGetValue("appId", out object? appIdObj);
            valueDict.TryGetValue("authToken", out object? authTokenObj);
            valueDict.TryGetValue("authUrl", out object? authUrlObj);
            valueDict.TryGetValue("websocketUrl", out object? websocketUrlObj);
            valueDict.TryGetValue("httpApiUrl", out object? httpApiUrlObj);
            valueDict.TryGetValue("httpApiKey", out object? httpApiKeyObj);
            valueDict.TryGetValue("mode", out object? modeObj);
            valueDict.TryGetValue("allowUntrustedCerts", out object? allowUntrustedCertsObj);

            var newConfig = new DittoDatabaseConfig(
                Id: idObj?.ToString() ?? Guid.NewGuid().ToString(),
                Name: nameObj?.ToString() ?? "Unnamed",
                DatabaseId: appIdObj?.ToString() ?? "",
                AuthToken: authTokenObj?.ToString() ?? "",
                AuthUrl: authUrlObj?.ToString() ?? "",
                WebsocketUrl: websocketUrlObj?.ToString() ?? "",
                HttpApiUrl: httpApiUrlObj?.ToString() ?? "",
                HttpApiKey: httpApiKeyObj?.ToString() ?? "",
                Mode: modeObj?.ToString() ?? "default",
                AllowUntrustedCerts: allowUntrustedCertsObj != null && bool.TryParse(allowUntrustedCertsObj.ToString(), out var allow) && allow
            );
            return newConfig;
        }
    }
}