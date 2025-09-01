using Avalonia.Threading;
using DittoSDK;
using EdgeStudio.Models;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace EdgeStudio.Data
{
    public class SystemService(IDittoManager _dittoManager)
        : ISystemService, IDisposable
    {
        private DittoStoreObserver? _syncStatusObserver;
        private bool _disposedValue;
        private List<string> _previousDocumentIds = new List<string>(); // Store only extracted IDs
        private DittoDiffer _differ = new DittoDiffer();


        public void CloseSelectedDatabase()
        {
            _previousDocumentIds.Clear();
            _syncStatusObserver?.Cancel();
            _syncStatusObserver = null;

            _differ.Dispose();
        }

        protected virtual void Dispose(bool disposing)
        {
            if (!_disposedValue)
            {
                if (disposing)
                {
                    CloseSelectedDatabase();
                }
                _disposedValue = true;
            }
        }
        public void Dispose()
        {
            // Do not change this code. Put cleanup code in 'Dispose(bool disposing)' method
            Dispose(disposing: true);
            GC.SuppressFinalize(this);
        }

        private static SyncStatusInfo GetDittoSyncStatusInfoFromQueryResult(DittoQueryResult result, int index)
        {
            var newItem = result.Items[index];
            var jsonString = newItem.JsonString();

            // Deserialize the JSON string to SyncStatusInfo
            var syncStatusInfo = System.Text.Json.JsonSerializer.Deserialize<SyncStatusInfo>(jsonString);
            if (syncStatusInfo == null)
            {
                throw new DeserializeException("Failed to deserialize SyncStatusInfo from JSON.");
            }

            return syncStatusInfo!;

        }

        public void RegisterLocalObservers(ObservableCollection<SyncStatusInfo> syncStatusInfos, Action<string> errorMessage)
        {
            //handle if the differ is null since a database might have closed and opened a new database
            if (_differ == null)
            {
                _differ = new DittoDiffer();
            }

            var ditto = _dittoManager.GetSelectedAppDitto();
            _syncStatusObserver = ditto.Store.RegisterObserver("SELECT * FROM system:data_sync_info ORDER BY documents.last_update_received_time desc", (result) =>
            {
                if (result != null)
                {
                    List<string> currentDocumentIds;

                    if (result.Items.Count > 0)
                    {
                        var diff = _differ.Diff(result.Items);

                        // Extract ALL data BEFORE dematerializing to avoid accessing dematerialized items
                        var extractedItems = new List<SyncStatusInfo>();
                        currentDocumentIds = new List<string>();

                        for (int i = 0; i < result.Items.Count; i++)
                        {
                            var item = result.Items[i];
                            var id = item.Value.TryGetValue("_id", out var idObj) ? idObj?.ToString() ?? "" : "";
                            var syncStatusInfo = GetDittoSyncStatusInfoFromQueryResult(result, i);
                            
                            extractedItems.Add(syncStatusInfo);
                            currentDocumentIds.Add(id);
                            
                            item.Dematerialize(); // Now safe to dematerialize after extraction
                        }

                        // Handle deletions using stored IDs from previous emission
                        foreach (var index in diff.Deletions)
                        {
                            if (index < _previousDocumentIds.Count)
                            {
                                var deletedId = _previousDocumentIds[index];

                                //make sure to do the update on the Main UI Thread
                                Dispatcher.UIThread.InvokeAsync(() =>
                                {
                                    var configToRemove = syncStatusInfos.FirstOrDefault(dc => dc.Id == deletedId);
                                    if (configToRemove != null)
                                    {
                                        syncStatusInfos.Remove(configToRemove);
                                    }
                                });
                            }
                        }

                        // Handle insertions using extracted data
                        foreach (var index in diff.Insertions)
                        {
                            var newSyncStatusInfo = extractedItems[index];
                            //make sure to do the update on the Main UI Thread
                            Dispatcher.UIThread.InvokeAsync(() =>
                            {
                                syncStatusInfos.Add(newSyncStatusInfo);
                            });
                        }

                        // Handle updates using extracted data with safe lookup
                        foreach (var index in diff.Updates)
                        {
                            var updatedId = currentDocumentIds[index];
                            var newSyncStatusInfo = extractedItems[index];
                            
                            Dispatcher.UIThread.InvokeAsync(() =>
                            {
                                var existingItem = syncStatusInfos.FirstOrDefault(dc => dc.Id == updatedId);
                                if (existingItem != null)
                                {
                                    var updateIndex = syncStatusInfos.IndexOf(existingItem);
                                    syncStatusInfos[updateIndex] = newSyncStatusInfo;
                                }
                                else
                                {
                                    // Fallback: treat as insertion if item not found (shouldn't happen but safer)
                                    syncStatusInfos.Add(newSyncStatusInfo);
                                }
                            });
                        }
                    }
                    else
                    {
                        currentDocumentIds = new List<string>();
                        // If we previously had items but now have none, clear the UI collection
                        if (_previousDocumentIds.Count > 0)
                        {
                            Dispatcher.UIThread.InvokeAsync(() =>
                            {
                                syncStatusInfos.Clear();
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
                }
            });
        }
    }
}
