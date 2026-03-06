using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using EdgeStudio.Shared.Data.Repositories;
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;

namespace EdgeStudio.ViewModels;

public partial class QueryViewModel : LoadableViewModelBase
{
    private readonly ICollectionsRepository _collectionsRepository;
    private int _queryCounter = 1;

    [ObservableProperty]
    private string _queryText = string.Empty;

    [ObservableProperty]
    private string _resultText = "Query View";

    [ObservableProperty]
    private QueryDocumentViewModel? _currentQueryDocument;

    /// <summary>
    /// Collection of open query document tabs.
    /// </summary>
    public ObservableCollection<QueryDocumentViewModel> QueryDocuments { get; } = new();

    /// <summary>
    /// Reference to the JSON results tool.
    /// </summary>
    public JsonResultsViewModel JsonResults { get; private set; }

    /// <summary>
    /// Reference to the Table results tool.
    /// </summary>
    public TableResultsViewModel TableResults { get; private set; }

    /// <summary>
    /// Reference to the Explain results tool.
    /// </summary>
    public ExplainResultsViewModel ExplainResults { get; private set; }

    /// <summary>
    /// Collections in the selected database.
    /// </summary>
    public ObservableCollection<CollectionInfo> Collections { get; } = new();

    /// <summary>
    /// Indicates whether there are collections to display.
    /// </summary>
    public bool HasCollections => Collections.Count > 0;

    public QueryViewModel(
        ICollectionsRepository collectionsRepository,
        IToastService? toastService = null) : base(toastService)
    {
        _collectionsRepository = collectionsRepository;

        // Initialize results ViewModels
        JsonResults = new JsonResultsViewModel();
        TableResults = new TableResultsViewModel();
        ExplainResults = new ExplainResultsViewModel();
    }

    protected override void OnInitialize()
    {
        base.OnInitialize();

        // Register observer for collections
        _collectionsRepository.RegisterObserver(Collections, error => ShowError(error));

        // Load collections
        _ = LoadCollectionsAsync();

        // Create initial query tab
        CreateInitialQuery();
    }

    private void CreateInitialQuery()
    {
        var initialQuery = new QueryDocumentViewModel($"Query {_queryCounter++}", JsonResults, TableResults, ExplainResults);
        QueryDocuments.Add(initialQuery);
        CurrentQueryDocument = initialQuery;
    }

    protected override void OnDeactivated()
    {
        base.OnDeactivated();
        // Clean up will be handled by repository disposal
    }

    private async Task LoadCollectionsAsync()
    {
        await ExecuteOperationAsync(
            async () =>
            {
                await _collectionsRepository.LoadCollectionsAsync();
                OnPropertyChanged(nameof(HasCollections));
            },
            errorMessage: "Failed to load collections",
            showSuccessToast: false);
    }

    [RelayCommand]
    private async Task ExecuteQuery()
    {
        if (string.IsNullOrWhiteSpace(QueryText))
        {
            ShowWarning("Please enter a query to execute");
            return;
        }

        await ExecuteOperationAsync(
            async () =>
            {
                // Placeholder for query execution
                await Task.Delay(500);
                ResultText = $"Results for query: {QueryText}";
            },
            errorMessage: "Failed to execute query",
            showSuccessToast: true,
            successMessage: "Query executed successfully");
    }

    [RelayCommand]
    private void NewQuery()
    {
        // Create new query document with results references
        var newQuery = new QueryDocumentViewModel($"Query {_queryCounter++}", JsonResults, TableResults, ExplainResults);

        // Add to collection and set as active
        QueryDocuments.Add(newQuery);
        CurrentQueryDocument = newQuery;
    }

    [RelayCommand]
    private void CloseQuery(QueryDocumentViewModel? queryDocument)
    {
        if (queryDocument == null || !QueryDocuments.Contains(queryDocument))
            return;

        // Don't allow closing the last query tab
        if (QueryDocuments.Count == 1)
        {
            ShowWarning("Cannot close the last query tab");
            return;
        }

        var index = QueryDocuments.IndexOf(queryDocument);
        QueryDocuments.Remove(queryDocument);

        // Select adjacent tab
        if (CurrentQueryDocument == queryDocument)
        {
            if (index >= QueryDocuments.Count)
                index = QueryDocuments.Count - 1;
            CurrentQueryDocument = QueryDocuments[index];
        }
    }
}
