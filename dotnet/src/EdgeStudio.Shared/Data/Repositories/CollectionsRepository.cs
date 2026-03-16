using Avalonia.Threading;
using DittoSDK;
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;
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
    public class CollectionsRepository(IDittoManager dittoManager, ILoggingService? logger = null)
        : ICollectionsRepository, ICloseDatabase, IDisposable
    {
        private readonly ILoggingService? _logger = logger;
        private ObservableCollection<CollectionInfo>? _collections;
        private Action<string>? _errorCallback;
        private DittoStoreObserver? _collectionsObserver;
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
                await RefreshAsync(ditto);

                // Register live observer so UI updates when collections change
                _collectionsObserver?.Cancel();
                _collectionsObserver = ditto.Store.RegisterObserver(
                    "SELECT * FROM __collections",
                    result => { result.Dispose(); _ = RefreshAsync(ditto); });
            }
            catch (Exception ex)
            {
                _errorCallback?.Invoke($"Error loading collections: {ex.Message}");
            }
        }

        private async Task RefreshAsync(Ditto ditto)
        {
            var names = await FetchCollectionNamesAsync(ditto);
            var countsByName = await FetchDocumentCountsAsync(ditto, names);
            var indexesByCollection = await FetchIndexesAsync(ditto);

            var infos = names
                .Select(name => new CollectionInfo
                {
                    Id = name,
                    Name = name,
                    DocumentCount = countsByName.TryGetValue(name, out var c) ? c : 0,
                    LastModified = DateTime.Now,
                    Indexes = indexesByCollection.TryGetValue(name, out var idx) ? idx : []
                })
                .ToList();

            await Dispatcher.UIThread.InvokeAsync(() =>
            {
                if (_collections == null) return;
                _collections.Clear();
                foreach (var info in infos)
                    _collections.Add(info);
            });
        }

        private static async Task<List<string>> FetchCollectionNamesAsync(Ditto ditto)
        {
            var result = await ditto.Store.ExecuteAsync("SELECT * FROM __collections");
            var names = result.Items
                .Select(item => item.Value.TryGetValue("name", out var n) ? n?.ToString() : null)
                .Where(n => n != null && !n.StartsWith("__", StringComparison.Ordinal))
                .Select(n => n!)
                .OrderBy(n => n, StringComparer.OrdinalIgnoreCase)
                .ToList();
            result.Dispose();
            return names;
        }

        private static async Task<Dictionary<string, int>> FetchDocumentCountsAsync(Ditto ditto, List<string> names)
        {
            var counts = new Dictionary<string, int>();
            foreach (var name in names)
            {
                try
                {
                    var result = await ditto.Store.ExecuteAsync($"SELECT COUNT(*) as numDocs FROM {name}");
                    if (result.Items.Count > 0 && result.Items[0].Value.TryGetValue("numDocs", out var n))
                        counts[name] = Convert.ToInt32(n);
                    result.Dispose();
                }
                catch (Exception)
                {
                    // Collection may be empty or inaccessible — skip
                }
            }
            return counts;
        }

        private static async Task<Dictionary<string, List<IndexInfo>>> FetchIndexesAsync(Ditto ditto)
        {
            var indexesByCollection = new Dictionary<string, List<IndexInfo>>();
            try
            {
                var result = await ditto.Store.ExecuteAsync("SELECT * FROM system:indexes");
                foreach (var item in result.Items)
                {
                    var collection = item.Value.TryGetValue("collection", out var col) ? col?.ToString() : null;
                    var rawId = item.Value.TryGetValue("_id", out var id) ? id?.ToString() : null;
                    if (collection == null || rawId == null) continue;

                    // SDK stores "collection.indexName" — strip the prefix
                    var dotIdx = rawId.IndexOf('.');
                    var indexName = dotIdx >= 0 ? rawId[(dotIdx + 1)..] : rawId;

                    var fields = new List<string>();
                    if (item.Value.TryGetValue("fields", out var rawFields) && rawFields is IEnumerable<object> fieldList)
                        fields.AddRange(fieldList.Select(f => f?.ToString()?.Trim('`') ?? string.Empty).Where(f => f.Length > 0));

                    if (!indexesByCollection.TryGetValue(collection, out var list))
                        indexesByCollection[collection] = list = [];
                    list.Add(new IndexInfo(indexName, fields));
                }
                result.Dispose();
            }
            catch (Exception)
            {
                // system:indexes may not be available in all SDK versions — return empty
            }
            return indexesByCollection;
        }

        public void CloseSelectedDatabase()
        {
            try { _collectionsObserver?.Cancel(); } catch { /* ignore */ }
            _collectionsObserver = null;
            _collections?.Clear();
            _collections = null;
            _errorCallback = null;
        }

        public Task CloseDatabaseAsync()
        {
            return Dispatcher.UIThread.InvokeAsync(() =>
            {
                try { _collectionsObserver?.Cancel(); } catch { /* ignore */ }
                _collectionsObserver = null;
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
