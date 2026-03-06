using Avalonia.Threading;
using DittoSDK;
using EdgeStudio.Shared.Models;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;

namespace EdgeStudio.Shared.Data.Repositories
{
    /// <summary>
    /// Repository for querying collections in the selected Ditto database.
    /// Note: Ditto doesn't provide a built-in way to enumerate all collections.
    /// This implementation queries known/discoverable collections.
    /// </summary>
    public class CollectionsRepository(IDittoManager dittoManager)
        : ICollectionsRepository, ICloseDatabase, IDisposable
    {
        private ObservableCollection<CollectionInfo>? _collections;
        private Action<string>? _errorCallback;
        private bool _disposed;

        public void RegisterObserver(ObservableCollection<CollectionInfo> collections, Action<string> errorMessage)
        {
            _collections = collections;
            _errorCallback = errorMessage;
        }

        public async Task LoadCollectionsAsync()
        {
            if (_collections == null || _errorCallback == null)
                return;

            try
            {
                var ditto = dittoManager.GetSelectedAppDitto();
                var collectionInfos = await DiscoverCollectionsAsync(ditto);

                await Dispatcher.UIThread.InvokeAsync(() =>
                {
                    _collections.Clear();
                    foreach (var collectionInfo in collectionInfos)
                    {
                        _collections.Add(collectionInfo);
                    }
                });
            }
            catch (Exception ex)
            {
                _errorCallback?.Invoke($"Error loading collections: {ex.Message}");
            }
        }

        private async Task<List<CollectionInfo>> DiscoverCollectionsAsync(Ditto ditto)
        {
            var collections = new List<CollectionInfo>();

            var knownCollections = new[]
            {
                "dittodatabaseconfigs",
                "dittodatabasesubscriptions",
                "dittoqueryhistory",
                "dittoqueryfavorites"
            };

            foreach (var collectionName in knownCollections)
            {
                try
                {
                    var query = $"SELECT COUNT(*) as count FROM {collectionName}";
                    var result = await ditto.Store.ExecuteAsync(query);

                    int count = 0;
                    if (result.Items.Count > 0)
                    {
                        var item = result.Items[0];
                        if (item.Value.TryGetValue("count", out var countObj))
                        {
                            count = Convert.ToInt32(countObj);
                        }
                    }
                    result.Dispose();

                    collections.Add(new CollectionInfo
                    {
                        Id = collectionName,
                        Name = FormatCollectionName(collectionName),
                        DocumentCount = count,
                        LastModified = DateTime.Now
                    });
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"Collection {collectionName} not accessible: {ex.Message}");
                }
            }

            return collections.OrderBy(c => c.Name).ToList();
        }

        private string FormatCollectionName(string collectionName)
        {
            if (collectionName.StartsWith("ditto"))
            {
                var name = collectionName.Substring(5);
                var formatted = string.Concat(name.Select((c, i) =>
                    i > 0 && char.IsUpper(c) ? " " + c : c.ToString()));
                return char.ToUpper(formatted[0]) + formatted.Substring(1);
            }
            return collectionName;
        }

        public void CloseSelectedDatabase()
        {
            _collections?.Clear();
            _collections = null;
            _errorCallback = null;
        }

        public Task CloseDatabaseAsync()
        {
            return Dispatcher.UIThread.InvokeAsync(() =>
            {
                _collections?.Clear();
                _collections = null;
                _errorCallback = null;
            }).GetTask();
        }

        public void Dispose()
        {
            if (!_disposed)
            {
                CloseSelectedDatabase();
                _disposed = true;
            }
        }
    }
}
