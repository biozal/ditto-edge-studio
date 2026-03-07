using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using System.Windows.Input;
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
        private readonly Lazy<ToolsViewModel> _toolsViewModelLazy;
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
            Lazy<ToolsViewModel> toolsViewModelLazy,
            Lazy<ISystemRepository> systemRepositoryLazy,
            IToastService? toastService = null)
            : base(toastService)
        {
            _dittoManager = dittoManager;
            _syncService = syncService;
            _navigationService = navigationService;
            _systemRepositoryLazy = systemRepositoryLazy;

            // Store lazy ViewModels - they will only be instantiated when .Value is accessed
            _navigationViewModelLazy = navigationViewModelLazy;
            _subscriptionViewModelLazy = subscriptionViewModelLazy;
            _subscriptionDetailsViewModelLazy = subscriptionDetailsViewModelLazy;
            _queryViewModelLazy = queryViewModelLazy;
            _observersViewModelLazy = observersViewModelLazy;
            _toolsViewModelLazy = toolsViewModelLazy;

            // Subscribe to connection count updates from the system repository
            _systemRepositoryLazy.Value.ConnectionsChanged += OnConnectionsChanged;

            // Register for navigation changes
            WeakReferenceMessenger.Default.Register<NavigationChangedMessage>(this, OnNavigationChanged);
            WeakReferenceMessenger.Default.Register<ListingItemSelectedMessage>(this, OnListingItemSelected);

            // Don't call UpdateCurrentViews in constructor - this would instantiate ViewModels prematurely
            // Views will be set when a database is actually selected
        }

        private void OnConnectionsChanged(object? sender, ConnectionsByTransport connections)
        {
            ConnectionsByTransport = connections;
        }

        public NavigationViewModel NavigationViewModel => _navigationViewModelLazy.Value;
        public SubscriptionViewModel SubscriptionViewModel => _subscriptionViewModelLazy.Value;
        public SubscriptionDetailsViewModel SubscriptionDetailsViewModel => _subscriptionDetailsViewModelLazy.Value;
        public QueryViewModel QueryViewModel => _queryViewModelLazy.Value;
        public ObserversViewModel ObserversViewModel => _observersViewModelLazy.Value;
        public ToolsViewModel ToolsViewModel => _toolsViewModelLazy.Value;

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
                    
                    // When database is selected, initialize ViewModels asynchronously for better performance
                    if (_selectedDatabase != null)
                    {
                        IsSyncEnabled = true;  // Sync auto-starts in DittoManager
                        OnPropertyChanged(nameof(SyncButtonTooltip));

                        // Initialize ViewModels on background thread, then set default view
                        _ = Task.Run(async () =>
                        {
                            await InitializeViewModelsAsync();

                            // Switch back to UI thread to update views
                            Avalonia.Threading.Dispatcher.UIThread.Post(() =>
                            {
                                // Default to Subscriptions view when database is first selected
                                UpdateCurrentViews(NavigationItemType.Subscriptions);
                            });
                        });
                    }
                    else
                    {
                        IsSyncEnabled = false;  // Reset on close
                        OnPropertyChanged(nameof(SyncButtonTooltip));

                        // Clear views when no database selected
                        CurrentListingViewModel = null;
                        CurrentDetailViewModel = null;
                    }
                }
            }
        }
        
        /// <summary>
        /// Gets the selected database name with null safety
        /// </summary>
        public string DatabaseName => _selectedDatabase?.Name ?? "Edge Studio Workspace";
        
        /// <summary>
        /// Gets the selected database ID with null safety
        /// </summary>
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
            // Send message instead of raising event to avoid memory leaks
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
        
        private void OnNavigationChanged(object recipient, NavigationChangedMessage message)
        {
            UpdateCurrentViews(message.NavigationType);
        }
        
        private void OnListingItemSelected(object recipient, ListingItemSelectedMessage message)
        {
            // Update detail view based on selected item
            switch (_navigationService.CurrentNavigationType)
            {
                case NavigationItemType.Subscriptions:
                    CurrentDetailViewModel = message.SelectedItem != null ? SubscriptionDetailsViewModel : null;
                    if (message.SelectedItem != null)
                    {
                        SubscriptionDetailsViewModel.Initialize();
                    }
                    break;
                case NavigationItemType.Query:
                    // Query detail view is always shown
                    break;
                case NavigationItemType.Observers:
                    CurrentDetailViewModel = message.SelectedItem != null ? ObserversViewModel : null;
                    break;
                case NavigationItemType.Tools:
                    CurrentDetailViewModel = message.SelectedItem != null ? ToolsViewModel : null;
                    break;
            }
        }

        private async Task InitializeViewModelsAsync()
        {
            // Pre-initialize all ViewModels on a background thread to avoid UI delays
            await Task.Run(() =>
            {
                // Access all lazy ViewModels to force initialization off the UI thread
                _ = SubscriptionViewModel;
                _ = SubscriptionDetailsViewModel;
                _ = QueryViewModel;
                _ = ObserversViewModel;
                _ = ToolsViewModel;
            });
        }
        
        private void UpdateCurrentViews(NavigationItemType navigationType)
        {
            // Deactivate previous ViewModels to cleanup observers/resources
            DeactivateCurrentViewModels();

            // Only show views when a database is actually selected
            if (_selectedDatabase == null)
            {
                CurrentListingViewModel = null;
                CurrentDetailViewModel = null;
                return;
            }

            // ViewModels should already be initialized, so this should be fast
            switch (navigationType)
            {
                case NavigationItemType.Subscriptions:
                    CurrentListingViewModel = SubscriptionViewModel;
                    // Automatically show the SubscriptionDetailsView (Peers view)
                    CurrentDetailViewModel = SubscriptionDetailsViewModel;
                    // Activate ViewModels to start observing
                    SubscriptionViewModel.Activate();
                    SubscriptionDetailsViewModel.Activate();
                    break;
                case NavigationItemType.Query:
                    CurrentListingViewModel = QueryViewModel;
                    // Automatically show the QueryView
                    CurrentDetailViewModel = QueryViewModel;
                    QueryViewModel.Activate();
                    break;
                case NavigationItemType.Observers:
                    CurrentListingViewModel = ObserversViewModel;
                    // Automatically show the ObserverDetailView
                    CurrentDetailViewModel = ObserversViewModel;
                    ObserversViewModel.Activate();
                    break;
                case NavigationItemType.Tools:
                    CurrentListingViewModel = ToolsViewModel;
                    // Automatically show the ToolsDetailView
                    CurrentDetailViewModel = ToolsViewModel;
                    ToolsViewModel.Activate();
                    break;
            }
        }

        private void DeactivateCurrentViewModels()
        {
            // Deactivate currently active ViewModels based on navigation type
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
                case NavigationItemType.Tools:
                    if (_toolsViewModelLazy.IsValueCreated)
                        ToolsViewModel.Deactivate();
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