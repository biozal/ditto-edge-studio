using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Data.Repositories;
using EdgeStudio.Shared.Messages;
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;
using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;

namespace EdgeStudio.ViewModels;

public partial class QueryViewModel : LoadableViewModelBase
{
    private readonly ICollectionsRepository _collectionsRepository;
    private readonly IQueryService? _queryService;
    private readonly IQueryMetricsService? _queryMetricsService;
    private readonly IAppMetricsService? _appMetricsService;
    private int _queryCounter = 1;
    private bool _httpAvailable;

    [ObservableProperty]
    private string _queryText = string.Empty;

    [ObservableProperty]
    private string _resultText = "Query View";

    [ObservableProperty]
    private int _currentPage = 1;

    [ObservableProperty]
    private int _pageSize = 25;

    [ObservableProperty]
    private int _totalResultCount = 0;

    public int PageCount => Math.Max(1, (int)Math.Ceiling((double)TotalResultCount / PageSize));

    public ObservableCollection<int> PageSizeOptions { get; } = new() { 25, 50, 100, 250 };

    partial void OnTotalResultCountChanged(int value)
    {
        OnPropertyChanged(nameof(PageCount));
        NextPageCommand.NotifyCanExecuteChanged();
        PreviousPageCommand.NotifyCanExecuteChanged();
    }

    partial void OnPageSizeChanged(int value)
    {
        OnPropertyChanged(nameof(PageCount));
        CurrentPage = 1;
        JsonResults.PageSize = value;
        TableResults.PageSize = value;
    }

    partial void OnCurrentPageChanged(int value)
    {
        NextPageCommand.NotifyCanExecuteChanged();
        PreviousPageCommand.NotifyCanExecuteChanged();
        JsonResults.CurrentPage = value;
        TableResults.CurrentPage = value;
    }

    [RelayCommand(CanExecute = nameof(CanGoNext))]
    private void NextPage()
    {
        if (CurrentPage < PageCount) CurrentPage++;
    }

    private bool CanGoNext() => CurrentPage < PageCount;

    [RelayCommand(CanExecute = nameof(CanGoPrevious))]
    private void PreviousPage()
    {
        if (CurrentPage > 1) CurrentPage--;
    }

    private bool CanGoPrevious() => CurrentPage > 1;

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
        IQueryService? queryService = null,
        IToastService? toastService = null,
        IQueryMetricsService? queryMetricsService = null,
        IAppMetricsService? appMetricsService = null) : base(toastService)
    {
        _collectionsRepository = collectionsRepository;
        _queryService = queryService;
        _queryMetricsService = queryMetricsService;
        _appMetricsService = appMetricsService;

        // Initialize results ViewModels
        JsonResults = new JsonResultsViewModel();
        TableResults = new TableResultsViewModel();
        ExplainResults = new ExplainResultsViewModel();

        WeakReferenceMessenger.Default.Register<QueryExecutedMessage>(this, OnQueryExecuted);
        WeakReferenceMessenger.Default.Register<LoadQueryRequestedMessage>(this, OnLoadQueryRequested);
        WeakReferenceMessenger.Default.Register<LoadAndExecuteQueryRequestedMessage>(this, OnLoadAndExecuteQueryRequested);
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

    private void OnQueryExecuted(object recipient, QueryExecutedMessage message)
    {
        TotalResultCount = message.Result.ResultCount;
        CurrentPage = 1;
    }

    private void OnLoadQueryRequested(object recipient, LoadQueryRequestedMessage message)
    {
        if (CurrentQueryDocument != null)
            CurrentQueryDocument.QueryText = message.QueryText;
        else
        {
            var doc = CreateQueryDocument($"Query {_queryCounter++}");
            QueryDocuments.Add(doc);
            CurrentQueryDocument = doc;
            doc.QueryText = message.QueryText;
        }
    }

    private async void OnLoadAndExecuteQueryRequested(object recipient, LoadAndExecuteQueryRequestedMessage message)
    {
        if (CurrentQueryDocument == null)
        {
            var doc = CreateQueryDocument($"Query {_queryCounter++}");
            QueryDocuments.Add(doc);
            CurrentQueryDocument = doc;
        }
        CurrentQueryDocument.QueryText = message.QueryText;
        await CurrentQueryDocument.ExecuteQueryCommand.ExecuteAsync(null);
    }

    private QueryDocumentViewModel CreateQueryDocument(string title, string queryText = "")
    {
        var doc = new QueryDocumentViewModel(title, JsonResults, TableResults, ExplainResults, _queryService, queryText, _queryMetricsService, _appMetricsService);
        doc.SetHttpAvailable(_httpAvailable);
        return doc;
    }

    private void CreateInitialQuery()
    {
        var initialQuery = CreateQueryDocument($"Query {_queryCounter++}");
        QueryDocuments.Add(initialQuery);
        CurrentQueryDocument = initialQuery;
    }

    public void SetDatabaseConfig(DittoDatabaseConfig? config)
    {
        _httpAvailable = !string.IsNullOrEmpty(config?.HttpApiUrl)
                      && !string.IsNullOrEmpty(config?.HttpApiKey);
        foreach (var doc in QueryDocuments)
            doc.SetHttpAvailable(_httpAvailable);
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

                // Auto-populate empty query with first collection
                if (Collections.Count > 0
                    && CurrentQueryDocument != null
                    && string.IsNullOrEmpty(CurrentQueryDocument.QueryText))
                {
                    var firstName = Collections[0].Name;
                    CurrentQueryDocument.QueryText = $"SELECT * FROM {firstName}";
                }
            },
            errorMessage: "Failed to load collections",
            showSuccessToast: false);
    }

    [RelayCommand]
    public async Task RefreshCollectionsAsync()
    {
        await LoadCollectionsAsync();
    }

    [RelayCommand]
    private void InsertQuery(string collectionName)
    {
        var text = $"SELECT * FROM {collectionName}";
        if (CurrentQueryDocument != null)
            CurrentQueryDocument.QueryText = text;
        else
            NewQuery();
    }

    [RelayCommand]
    private void NewQuery()
    {
        var newQuery = CreateQueryDocument($"Query {_queryCounter++}");
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

    protected override void OnDisposing()
    {
        WeakReferenceMessenger.Default.UnregisterAll(this);
        base.OnDisposing();
    }
}
