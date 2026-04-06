using Avalonia.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Messages;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;

namespace EdgeStudio.ViewModels
{
    /// <summary>
    /// A single field leaf node inside an index.
    /// </summary>
    public class IndexFieldNode
    {
        public string Name { get; }
        public IndexFieldNode(string name) => Name = name;
    }

    /// <summary>
    /// An index node inside a collection — expandable to reveal fields.
    /// </summary>
    public partial class IndexTreeNode : ObservableObject
    {
        [ObservableProperty]
        private bool _isExpanded;

        public string Collection { get; }
        public string Name { get; }
        public IReadOnlyList<IndexFieldNode> Fields { get; }

        public IndexTreeNode(string collection, string name, IEnumerable<string> fields)
        {
            Collection = collection;
            Name = name;
            Fields = fields.Select(f => new IndexFieldNode(f)).ToList();
        }

        [RelayCommand]
        private void ToggleExpand() => IsExpanded = !IsExpanded;
    }

    /// <summary>
    /// A collection node — expandable to reveal its indexes.
    /// </summary>
    public partial class CollectionTreeNode : ObservableObject
    {
        [ObservableProperty]
        private bool _isExpanded;

        public string Name { get; }
        public ObservableCollection<IndexTreeNode> Indexes { get; } = new();
        public bool HasIndexes => Indexes.Count > 0;

        public CollectionTreeNode(string name) => Name = name;

        [RelayCommand]
        private void ToggleExpand() => IsExpanded = !IsExpanded;
    }

    /// <summary>
    /// ViewModel for the Indexes tool panel in the Inspector.
    /// </summary>
    public partial class IndexesToolViewModel : ObservableObject
    {
        private readonly IDittoManager _dittoManager;

        /// <summary>Tree of collections → indexes → fields shown in the Inspector.</summary>
        public ObservableCollection<CollectionTreeNode> CollectionNodes { get; } = new();

        /// <summary>Flat list of collection names for the create-index dropdown.</summary>
        public ObservableCollection<string> AvailableCollections { get; } = new();

        [ObservableProperty]
        private bool _isLoading;

        [ObservableProperty]
        private bool _hasCollections;

        [ObservableProperty]
        private string _newIndexCollection = string.Empty;

        [ObservableProperty]
        private string _newIndexField = string.Empty;

        [ObservableProperty]
        private string _errorMessage = string.Empty;

        [ObservableProperty]
        private bool _hasError;

        public IndexesToolViewModel(IDittoManager dittoManager)
        {
            _dittoManager = dittoManager;
        }

        /// <summary>Called by EdgeStudioViewModel when a database is initialized.</summary>
        public async Task LoadAsync()
        {
            if (IsLoading) return;
            IsLoading = true;
            try
            {
                await FetchDataAsync();
            }
            finally
            {
                IsLoading = false;
            }
        }

        private async Task FetchDataAsync()
        {
            ClearError();
            try
            {
                var ditto = _dittoManager.GetSelectedAppDitto();

                // Fetch all collection names
                var names = await FetchCollectionNamesAsync(ditto);

                // Fetch indexes grouped by collection
                var indexesByCollection = await FetchIndexesByCollectionAsync(ditto);

                await Dispatcher.UIThread.InvokeAsync(() =>
                {
                    // Dropdown list for the create-form
                    AvailableCollections.Clear();
                    foreach (var name in names)
                        AvailableCollections.Add(name);

                    // Rebuild the tree
                    CollectionNodes.Clear();
                    foreach (var name in names)
                    {
                        var node = new CollectionTreeNode(name);
                        if (indexesByCollection.TryGetValue(name, out var indexes))
                        {
                            foreach (var idx in indexes.OrderBy(i => i.Name))
                                node.Indexes.Add(idx);
                        }
                        CollectionNodes.Add(node);
                    }

                    HasCollections = CollectionNodes.Count > 0;
                });
            }
            catch (Exception)
            {
                // Database may not be ready yet — silently ignore
            }
        }

        private static async Task<List<string>> FetchCollectionNamesAsync(DittoSDK.Ditto ditto)
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

        private static async Task<Dictionary<string, List<IndexTreeNode>>> FetchIndexesByCollectionAsync(DittoSDK.Ditto ditto)
        {
            var result_dict = new Dictionary<string, List<IndexTreeNode>>();
            try
            {
                var result = await ditto.Store.ExecuteAsync("SELECT * FROM system:indexes");
                foreach (var item in result.Items)
                {
                    var collection = item.Value.TryGetValue("collection", out var col) ? col?.ToString() : null;
                    var rawId = item.Value.TryGetValue("_id", out var id) ? id?.ToString() : null;
                    if (collection == null || rawId == null) continue;

                    var dotIdx = rawId.IndexOf('.');
                    var indexName = dotIdx >= 0 ? rawId[(dotIdx + 1)..] : rawId;

                    var fields = new List<string>();
                    if (item.Value.TryGetValue("fields", out var rawFields) && rawFields is IEnumerable<object> fieldList)
                        fields.AddRange(fieldList.Select(ExtractFieldName).Where(f => f.Length > 0));

                    if (!result_dict.TryGetValue(collection, out var list))
                        result_dict[collection] = list = [];
                    list.Add(new IndexTreeNode(collection, indexName, fields));
                }
                result.Dispose();
            }
            catch (Exception)
            {
                // system:indexes may not be available — return empty
            }
            return result_dict;
        }

        private static string ExtractFieldName(object? f)
        {
            // SDK returns each field entry as: { "direction": "asc", "key": ["fieldName"] }
            if (f is IDictionary<string, object> dict &&
                dict.TryGetValue("key", out var keyVal) &&
                keyVal is IEnumerable<object> keyList)
            {
                return keyList.FirstOrDefault()?.ToString()?.Trim('`') ?? string.Empty;
            }
            return f?.ToString()?.Trim('`') ?? string.Empty;
        }

        [RelayCommand]
        private async Task RefreshAsync() => await LoadAsync();

        [RelayCommand]
        private void Cancel()
        {
            NewIndexCollection = string.Empty;
            NewIndexField = string.Empty;
            ClearError();
            WeakReferenceMessenger.Default.Send(new HideIndexFormMessage());
        }

        [RelayCommand]
        private async Task CreateIndexAsync()
        {
            var collection = NewIndexCollection.Trim();
            var field = NewIndexField.Trim();
            if (string.IsNullOrEmpty(collection) || string.IsNullOrEmpty(field))
            {
                SetError("Collection name and field name are required.");
                return;
            }

            IsLoading = true;
            try
            {
                ClearError();
                var ditto = _dittoManager.GetSelectedAppDitto();
                var indexName = $"idx_{collection}_{field}";
                await ditto.Store.ExecuteAsync($"CREATE INDEX {indexName} ON {collection}({field})");

                NewIndexField = string.Empty;
                await FetchDataAsync();
                WeakReferenceMessenger.Default.Send(new RefreshCollectionsRequestedMessage());
                WeakReferenceMessenger.Default.Send(new HideIndexFormMessage());
            }
            catch (Exception ex)
            {
                SetError($"Failed to create index: {ex.Message}");
            }
            finally
            {
                IsLoading = false;
            }
        }

        [RelayCommand]
        private async Task DropIndexAsync(IndexTreeNode node)
        {
            IsLoading = true;
            try
            {
                ClearError();
                var ditto = _dittoManager.GetSelectedAppDitto();
                await ditto.Store.ExecuteAsync($"DROP INDEX {node.Collection}.{node.Name}");
                await FetchDataAsync();
                WeakReferenceMessenger.Default.Send(new RefreshCollectionsRequestedMessage());
            }
            catch (Exception ex)
            {
                SetError($"Failed to drop index: {ex.Message}");
            }
            finally
            {
                IsLoading = false;
            }
        }

        private void SetError(string message)
        {
            ErrorMessage = message;
            HasError = true;
        }

        private void ClearError()
        {
            ErrorMessage = string.Empty;
            HasError = false;
        }
    }
}
