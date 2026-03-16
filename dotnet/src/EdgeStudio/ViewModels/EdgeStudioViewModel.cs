using System;
using System.IO;
using System.Threading.Tasks;
using Avalonia.Platform;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Data.Repositories;
using EdgeStudio.Shared.Messages;
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;

namespace EdgeStudio.ViewModels
{
    public partial class EdgeStudioViewModel : DisposableViewModelBase
    {
        private readonly IDittoManager _dittoManager;
        private readonly ISyncService _syncService;
        private readonly INavigationService _navigationService;
        private readonly Lazy<NavigationViewModel> _navigationViewModelLazy;
        private readonly Lazy<SubscriptionViewModel> _subscriptionViewModelLazy;
        private readonly Lazy<SubscriptionDetailsViewModel> _subscriptionDetailsViewModelLazy;
        private readonly Lazy<QueryViewModel> _queryViewModelLazy;
        private readonly Lazy<ObserversViewModel> _observersViewModelLazy;
        private readonly Lazy<LoggingViewModel> _loggingViewModelLazy;
        private readonly Lazy<AppMetricsViewModel> _appMetricsViewModelLazy;
        private readonly Lazy<QueryMetricsViewModel> _queryMetricsViewModelLazy;
        private readonly Lazy<HistoryToolViewModel> _historyToolViewModelLazy;
        private readonly Lazy<FavoritesToolViewModel> _favoritesToolViewModelLazy;
        private readonly Lazy<ISystemRepository> _systemRepositoryLazy;

        private DittoDatabaseConfig? _selectedDatabase;
        private object? _currentListingViewModel;
        private object? _currentDetailViewModel;

        [ObservableProperty]
        private bool _isSyncEnabled = false;

        [ObservableProperty]
        private bool _isSyncButtonEnabled = true;

        [ObservableProperty]
        private ConnectionsByTransport _connectionsByTransport = ConnectionsByTransport.Empty;

        [ObservableProperty]
        private bool _isInspectorVisible = false;

        [ObservableProperty]
        private bool _isListingPanelVisible = true;

        [ObservableProperty]
        private object _currentBottomBarContent = ConnectionsByTransport.Empty;

        [ObservableProperty]
        private bool _isLoggingActive = false;

        [ObservableProperty]
        private string _loggingHelpContent = string.Empty;

        [ObservableProperty]
        private bool _isSubscriptionActive = false;

        [ObservableProperty]
        private string _subscriptionHelpContent = string.Empty;

        [ObservableProperty]
        private bool _isQueryActive = false;

        [ObservableProperty]
        private string _queryHelpContent = string.Empty;

        /// <summary>
        /// Selected tab index for the query inspector panel.
        /// 0=History, 1=Favorites, 2=JSON Viewer, 3=Metrics, 4=Help
        /// </summary>
        [ObservableProperty]
        private int _selectedQueryInspectorTabIndex = 0;

        public bool IsStandardInspectorVisible => !IsLoggingActive && !IsSubscriptionActive && !IsQueryActive;

        partial void OnIsLoggingActiveChanged(bool value) => OnPropertyChanged(nameof(IsStandardInspectorVisible));
        partial void OnIsSubscriptionActiveChanged(bool value) => OnPropertyChanged(nameof(IsStandardInspectorVisible));
        partial void OnIsQueryActiveChanged(bool value) => OnPropertyChanged(nameof(IsStandardInspectorVisible));

        public string SyncButtonTooltip => IsSyncEnabled ? "Stop Sync" : "Start Sync";

        public EdgeStudioViewModel(
            IDittoManager dittoManager,
            ISyncService syncService,
            INavigationService navigationService,
            Lazy<NavigationViewModel> navigationViewModelLazy,
            Lazy<SubscriptionViewModel> subscriptionViewModelLazy,
            Lazy<SubscriptionDetailsViewModel> subscriptionDetailsViewModelLazy,
            Lazy<QueryViewModel> queryViewModelLazy,
            Lazy<ObserversViewModel> observersViewModelLazy,
            Lazy<LoggingViewModel> loggingViewModelLazy,
            Lazy<AppMetricsViewModel> appMetricsViewModelLazy,
            Lazy<QueryMetricsViewModel> queryMetricsViewModelLazy,
            Lazy<HistoryToolViewModel> historyToolViewModelLazy,
            Lazy<FavoritesToolViewModel> favoritesToolViewModelLazy,
            Lazy<ISystemRepository> systemRepositoryLazy,
            IToastService? toastService = null)
            : base(toastService)
        {
            _dittoManager = dittoManager;
            _syncService = syncService;
            _navigationService = navigationService;
            _systemRepositoryLazy = systemRepositoryLazy;

            _navigationViewModelLazy = navigationViewModelLazy;
            _subscriptionViewModelLazy = subscriptionViewModelLazy;
            _subscriptionDetailsViewModelLazy = subscriptionDetailsViewModelLazy;
            _queryViewModelLazy = queryViewModelLazy;
            _observersViewModelLazy = observersViewModelLazy;
            _loggingViewModelLazy = loggingViewModelLazy;
            _appMetricsViewModelLazy = appMetricsViewModelLazy;
            _queryMetricsViewModelLazy = queryMetricsViewModelLazy;
            _historyToolViewModelLazy = historyToolViewModelLazy;
            _favoritesToolViewModelLazy = favoritesToolViewModelLazy;

            _systemRepositoryLazy.Value.ConnectionsChanged += OnConnectionsChanged;

            WeakReferenceMessenger.Default.Register<NavigationChangedMessage>(this, OnNavigationChanged);
            WeakReferenceMessenger.Default.Register<ListingItemSelectedMessage>(this, OnListingItemSelected);
            WeakReferenceMessenger.Default.Register<DocumentDoubleClickedMessage>(this, OnDocumentDoubleClicked);
        }

        private void OnConnectionsChanged(object? sender, ConnectionsByTransport connections)
        {
            ConnectionsByTransport = connections;
            if (!IsLoggingActive && !IsQueryActive)
                CurrentBottomBarContent = connections;
        }

        public NavigationViewModel NavigationViewModel => _navigationViewModelLazy.Value;
        public SubscriptionViewModel SubscriptionViewModel => _subscriptionViewModelLazy.Value;
        public SubscriptionDetailsViewModel SubscriptionDetailsViewModel => _subscriptionDetailsViewModelLazy.Value;
        public QueryViewModel QueryViewModel => _queryViewModelLazy.Value;
        public ObserversViewModel ObserversViewModel => _observersViewModelLazy.Value;
        public LoggingViewModel LoggingViewModel => _loggingViewModelLazy.Value;
        public AppMetricsViewModel AppMetricsViewModel => _appMetricsViewModelLazy.Value;
        public QueryMetricsViewModel QueryMetricsViewModel => _queryMetricsViewModelLazy.Value;
        public HistoryToolViewModel HistoryToolViewModel => _historyToolViewModelLazy.Value;
        public FavoritesToolViewModel FavoritesToolViewModel => _favoritesToolViewModelLazy.Value;

        public DittoDatabaseConfig? SelectedDatabase
        {
            get => _selectedDatabase;
            set
            {
                if (_selectedDatabase != value)
                {
                    _selectedDatabase = value;
                    OnPropertyChanged();
                    OnPropertyChanged(nameof(DatabaseName));
                    OnPropertyChanged(nameof(DatabaseId));

                    if (_selectedDatabase != null)
                    {
                        IsSyncEnabled = true;
                        OnPropertyChanged(nameof(SyncButtonTooltip));

                        _ = Task.Run(async () =>
                        {
                            await InitializeViewModelsAsync();

                            Avalonia.Threading.Dispatcher.UIThread.Post(() =>
                            {
                                QueryViewModel.SetDatabaseConfig(_selectedDatabase);
                                UpdateCurrentViews(NavigationItemType.Subscriptions);
                            });
                        });
                    }
                    else
                    {
                        IsSyncEnabled = false;
                        OnPropertyChanged(nameof(SyncButtonTooltip));
                        CurrentListingViewModel = null;
                        CurrentDetailViewModel = null;
                    }
                }
            }
        }

        public string DatabaseName => _selectedDatabase?.Name ?? "Edge Studio Workspace";
        public string DatabaseId => _selectedDatabase?.DatabaseId ?? "Not connected";

        public object? CurrentListingViewModel
        {
            get => _currentListingViewModel;
            set
            {
                if (_currentListingViewModel != value)
                {
                    _currentListingViewModel = value;
                    OnPropertyChanged();
                }
            }
        }

        public object? CurrentDetailViewModel
        {
            get => _currentDetailViewModel;
            set
            {
                if (_currentDetailViewModel != value)
                {
                    _currentDetailViewModel = value;
                    OnPropertyChanged();
                }
            }
        }

        [RelayCommand]
        private void CloseDatabase()
        {
            WeakReferenceMessenger.Default.Send(new CloseDatabaseRequestedMessage());
        }

        [RelayCommand]
        private void ToggleSync()
        {
            if (_selectedDatabase == null)
            {
                ShowWarning("No database connected", "Sync");
                return;
            }

            try
            {
                if (IsSyncEnabled)
                {
                    _syncService.StopSync();
                    IsSyncEnabled = false;
                    ShowInfo("Sync stopped", "Synchronization");
                }
                else
                {
                    _syncService.StartSync();
                    IsSyncEnabled = true;
                    ShowSuccess("Sync started", "Synchronization");
                }

                OnPropertyChanged(nameof(SyncButtonTooltip));
            }
            catch (Exception ex)
            {
                ShowError($"Sync operation failed: {ex.Message}", "Sync Error");
                IsSyncEnabled = !IsSyncEnabled;
                OnPropertyChanged(nameof(SyncButtonTooltip));
            }
        }

        [RelayCommand]
        private void ToggleInspector()
        {
            IsInspectorVisible = !IsInspectorVisible;
        }

        [RelayCommand]
        private void NewQueryTab()
        {
            if (_navigationService.CurrentNavigationType != NavigationItemType.Query)
                UpdateCurrentViews(NavigationItemType.Query);
            QueryViewModel.NewQueryCommand.Execute(null);
        }

        [RelayCommand]
        private void AddSubscription()
        {
            if (_navigationService.CurrentNavigationType != NavigationItemType.Subscriptions)
                UpdateCurrentViews(NavigationItemType.Subscriptions);
            SubscriptionViewModel.AddSubscriptionCommand.Execute(null);
        }

        [RelayCommand]
        private void AddObserver() { }

        [RelayCommand]
        private void AddIndex() { }

        [RelayCommand]
        private void ImportSubscriptionsQr() { }

        [RelayCommand]
        private void ImportSubscriptionsServer() { }

        [RelayCommand]
        private void ImportJsonData() { }

        private void OnDocumentDoubleClicked(object recipient, DocumentDoubleClickedMessage message)
        {
            // Open inspector if hidden
            if (!IsInspectorVisible)
                IsInspectorVisible = true;

            // Navigate to JSON Viewer tab (index 2 in the query inspector panel)
            SelectedQueryInspectorTabIndex = 2;
        }

        private void OnNavigationChanged(object recipient, NavigationChangedMessage message)
        {
            UpdateCurrentViews(message.NavigationType);
        }

        private void OnListingItemSelected(object recipient, ListingItemSelectedMessage message)
        {
            switch (_navigationService.CurrentNavigationType)
            {
                case NavigationItemType.Subscriptions:
                    CurrentDetailViewModel = message.SelectedItem != null ? SubscriptionDetailsViewModel : null;
                    if (message.SelectedItem != null)
                        SubscriptionDetailsViewModel.Initialize();
                    break;
                case NavigationItemType.Query:
                    break;
                case NavigationItemType.Observers:
                    CurrentDetailViewModel = message.SelectedItem != null ? ObserversViewModel : null;
                    break;
                case NavigationItemType.AppMetrics:
                    CurrentDetailViewModel = message.SelectedItem != null ? AppMetricsViewModel : null;
                    break;
            }
        }

        private async Task InitializeViewModelsAsync()
        {
            await Task.Run(() =>
            {
                _ = SubscriptionViewModel;
                _ = SubscriptionDetailsViewModel;
                _ = QueryViewModel;
                _ = ObserversViewModel;
                _ = LoggingViewModel;
                _ = AppMetricsViewModel;
                _ = QueryMetricsViewModel;
                _ = HistoryToolViewModel;
                _ = FavoritesToolViewModel;
            });
        }

        private void UpdateCurrentViews(NavigationItemType navigationType)
        {
            DeactivateCurrentViewModels();

            if (_selectedDatabase == null)
            {
                CurrentListingViewModel = null;
                CurrentDetailViewModel = null;
                return;
            }

            switch (navigationType)
            {
                case NavigationItemType.Subscriptions:
                    CurrentListingViewModel = SubscriptionViewModel;
                    CurrentDetailViewModel = SubscriptionDetailsViewModel;
                    SetStandardNavLayout();
                    IsSubscriptionActive = true;
                    EnsureSubscriptionHelpLoaded();
                    SubscriptionViewModel.Activate();
                    SubscriptionDetailsViewModel.Activate();
                    break;
                case NavigationItemType.Query:
                    CurrentListingViewModel = QueryViewModel;
                    CurrentDetailViewModel = QueryViewModel;
                    SetStandardNavLayout();
                    IsQueryActive = true;
                    CurrentBottomBarContent = QueryViewModel;
                    EnsureQueryHelpLoaded();
                    QueryViewModel.Activate();
                    break;
                case NavigationItemType.Observers:
                    CurrentListingViewModel = ObserversViewModel;
                    CurrentDetailViewModel = ObserversViewModel;
                    SetStandardNavLayout();
                    ObserversViewModel.Activate();
                    break;
                case NavigationItemType.Logging:
                    CurrentListingViewModel = null;
                    CurrentDetailViewModel = LoggingViewModel;
                    IsListingPanelVisible = false;
                    CurrentBottomBarContent = LoggingViewModel;
                    IsLoggingActive = true;
                    LoggingViewModel.Activate();
                    EnsureLoggingHelpLoaded();
                    break;
                case NavigationItemType.AppMetrics:
                    CurrentListingViewModel = AppMetricsViewModel;
                    CurrentDetailViewModel = AppMetricsViewModel;
                    SetStandardNavLayout();
                    AppMetricsViewModel.Activate();
                    break;
                case NavigationItemType.QueryMetrics:
                    CurrentListingViewModel = QueryMetricsViewModel;
                    CurrentDetailViewModel = QueryMetricsViewModel;
                    SetStandardNavLayout();
                    QueryMetricsViewModel.Activate();
                    break;
            }
        }

        private void SetStandardNavLayout()
        {
            IsListingPanelVisible = true;
            CurrentBottomBarContent = ConnectionsByTransport;
            IsLoggingActive = false;
            IsSubscriptionActive = false;
            IsQueryActive = false;
        }

        private static readonly Uri LoggingHelpUri = new("avares://EdgeStudio/Assets/Help/logging.md");

        private void EnsureLoggingHelpLoaded()
        {
            if (!string.IsNullOrEmpty(LoggingHelpContent)) return;
            try
            {
                using var stream = AssetLoader.Open(LoggingHelpUri);
                using var reader = new StreamReader(stream);
                LoggingHelpContent = reader.ReadToEnd();
            }
            catch
            {
                LoggingHelpContent = "# Logging\n\nHelp content unavailable.";
            }
        }

        private static readonly Uri QueryHelpUri = new("avares://EdgeStudio/Assets/Help/query.md");

        private void EnsureQueryHelpLoaded()
        {
            if (!string.IsNullOrEmpty(QueryHelpContent)) return;
            try
            {
                using var stream = AssetLoader.Open(QueryHelpUri);
                using var reader = new StreamReader(stream);
                QueryHelpContent = reader.ReadToEnd();
            }
            catch
            {
                QueryHelpContent = "# Query\n\nHelp content unavailable.";
            }
        }

        private static readonly Uri SubscriptionHelpUri = new("avares://EdgeStudio/Assets/Help/subscription.md");

        private void EnsureSubscriptionHelpLoaded()
        {
            if (!string.IsNullOrEmpty(SubscriptionHelpContent)) return;
            try
            {
                using var stream = AssetLoader.Open(SubscriptionHelpUri);
                using var reader = new StreamReader(stream);
                SubscriptionHelpContent = reader.ReadToEnd();
            }
            catch
            {
                SubscriptionHelpContent = "# Subscriptions\n\nHelp content unavailable.";
            }
        }

        private void DeactivateCurrentViewModels()
        {
            switch (_navigationService.CurrentNavigationType)
            {
                case NavigationItemType.Subscriptions:
                    if (_subscriptionViewModelLazy.IsValueCreated)
                        SubscriptionViewModel.Deactivate();
                    if (_subscriptionDetailsViewModelLazy.IsValueCreated)
                        SubscriptionDetailsViewModel.Deactivate();
                    break;
                case NavigationItemType.Query:
                    if (_queryViewModelLazy.IsValueCreated)
                        QueryViewModel.Deactivate();
                    break;
                case NavigationItemType.Observers:
                    if (_observersViewModelLazy.IsValueCreated)
                        ObserversViewModel.Deactivate();
                    break;
                case NavigationItemType.Logging:
                    if (_loggingViewModelLazy.IsValueCreated)
                        LoggingViewModel.Deactivate();
                    break;
                case NavigationItemType.AppMetrics:
                    if (_appMetricsViewModelLazy.IsValueCreated)
                        AppMetricsViewModel.Deactivate();
                    break;
                case NavigationItemType.QueryMetrics:
                    if (_queryMetricsViewModelLazy.IsValueCreated)
                        QueryMetricsViewModel.Deactivate();
                    break;
            }
        }

        protected override void OnDisposing()
        {
            if (_systemRepositoryLazy.IsValueCreated)
                _systemRepositoryLazy.Value.ConnectionsChanged -= OnConnectionsChanged;

            base.OnDisposing();
        }
    }
}
