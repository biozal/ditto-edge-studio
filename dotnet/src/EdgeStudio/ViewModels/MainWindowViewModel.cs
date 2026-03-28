using System;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Linq;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Services;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Data.Repositories;
using EdgeStudio.Shared.Messages;
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;

namespace EdgeStudio.ViewModels
{
    public partial class MainWindowViewModel : LoadableViewModelBase
    {
        private readonly IDatabaseRepository _databaseRepository;
        private readonly IDittoManager _dittoManager;
        private readonly ISystemRepository _systemRepository;
        private readonly ISubscriptionRepository _subscriptionRepository;
        private readonly IHistoryRepository _historyRepository;
        private readonly IFavoritesRepository _favoritesRepository;
        private readonly IQrCodeService _qrCodeService;
        private readonly ILogCaptureService _logCaptureService;

        public MainWindowViewModel(
            IDittoManager dittoManager,
            IDatabaseRepository databaseRepository,
            ISystemRepository systemRepository,
            ISubscriptionRepository subscriptionRepository,
            IHistoryRepository historyRepository,
            IFavoritesRepository favoritesRepository,
            IQrCodeService qrCodeService,
            ILogCaptureService logCaptureService,
            IToastService? toastService = null)
            : base(toastService)
        {
            _databaseRepository = databaseRepository ?? throw new ArgumentNullException(nameof(databaseRepository));
            _dittoManager = dittoManager ?? throw new ArgumentNullException(nameof(dittoManager));
            _systemRepository = systemRepository ?? throw new ArgumentNullException(nameof(systemRepository));
            _subscriptionRepository = subscriptionRepository ?? throw new ArgumentNullException(nameof(subscriptionRepository));
            _historyRepository = historyRepository ?? throw new ArgumentNullException(nameof(historyRepository));
            _favoritesRepository = favoritesRepository ?? throw new ArgumentNullException(nameof(favoritesRepository));
            _qrCodeService = qrCodeService ?? throw new ArgumentNullException(nameof(qrCodeService));
            _logCaptureService = logCaptureService ?? throw new ArgumentNullException(nameof(logCaptureService));
            
            DatabaseConfigs = new ObservableCollection<DittoDatabaseConfig>();
            DatabaseFormModel = new DatabaseFormModel();
            
            // Subscribe to collection changes to update HasDatabaseConfigs
            DatabaseConfigs.CollectionChanged += (s, e) => OnPropertyChanged(nameof(HasDatabaseConfigs));
            
            // Initialize async operations
            _ = InitializeAsync();
        }

        [ObservableProperty]
        private bool isInitializingDatabase;

        [ObservableProperty]
        private bool isClosingDatabase;

        [ObservableProperty]
        private DittoDatabaseConfig? selectedDatabaseConfig;

        private DittoDatabaseConfig? _selectedDatabase;
        
        public DittoDatabaseConfig? SelectedDatabase
        {
            get => _selectedDatabase;
            set
            {
                if (SetProperty(ref _selectedDatabase, value))
                {
                    OnPropertyChanged(nameof(HasSelectedDatabase));
                    
                    // Trigger async initialization if a database is selected
                    if (value != null)
                    {
                        _ = InitializeSelectedDatabaseAsync(value);
                    }
                    else
                    {
                        // Close the currently selected database when setting to null
                        // Call CloseSelectedDatabase on all repositories that implement ICloseDatabase
                        _systemRepository.CloseSelectedDatabase();
                        _subscriptionRepository.CloseSelectedDatabase();
                        _historyRepository.CloseSelectedDatabase();
                        _favoritesRepository.CloseSelectedDatabase();
                        _dittoManager.CloseSelectedDatabase();
                    }
                }
            }
        }

        public ObservableCollection<DittoDatabaseConfig> DatabaseConfigs { get; }
        
        /// <summary>
        /// Returns true when a database is selected for navigation
        /// </summary>
        public bool HasSelectedDatabase => SelectedDatabase != null;
        
        /// <summary>
        /// Form model for add/edit database dialog
        /// </summary>
        public DatabaseFormModel DatabaseFormModel { get; }
        
        /// <summary>
        /// Returns true when there are no database configurations (for empty state visibility)
        /// </summary>
        public bool HasDatabaseConfigs => DatabaseConfigs.Count == 0;
        
        // Events converted to WeakReferenceMessenger pattern for better memory management


        [RelayCommand]
        private void SelectDatabase(DittoDatabaseConfig config)
        {
            if (config != null)
            {
                SelectedDatabase = config;
                OnPropertyChanged(nameof(HasSelectedDatabase));
            }
        }
        
        [RelayCommand]
        private void AddDatabase()
        {
            DatabaseFormModel.Reset();
            WeakReferenceMessenger.Default.Send(new ShowAddDatabaseFormMessage());
        }
        
        [RelayCommand]
        private void EditDatabase(DittoDatabaseConfig config)
        {
            if (config == null)
            {
                return;
            }
            
            DatabaseFormModel.LoadFromConfig(config);
            WeakReferenceMessenger.Default.Send(new ShowEditDatabaseFormMessage());
        }
        
        [RelayCommand]
        private async Task DeleteDatabaseAsync(DittoDatabaseConfig config)
        {
            if (config == null)
            {
                ShowError("Cannot delete: database configuration is null.");
                return;
            }

            await ExecuteOperationAsync(
                async () => await _databaseRepository.DeleteDittoDatabaseConfig(config),
                errorMessage: "Failed to delete database configuration",
                showLoadingState: false,
                showSuccessToast: true,
                successMessage: $"Database '{config.Name}' deleted successfully");
        }
        
        [RelayCommand]
        private async Task SaveDatabaseAsync()
        {
            // Validate always-required fields
            if (string.IsNullOrWhiteSpace(DatabaseFormModel.Name) ||
                string.IsNullOrWhiteSpace(DatabaseFormModel.DatabaseId) ||
                string.IsNullOrWhiteSpace(DatabaseFormModel.AuthToken))
            {
                ShowError("Please fill in all required fields (Name, Database ID, Auth Token).");
                return;
            }

            // Validate server-mode-specific required fields
            if (DatabaseFormModel.Mode == "server" &&
                (string.IsNullOrWhiteSpace(DatabaseFormModel.AuthUrl) ||
                 string.IsNullOrWhiteSpace(DatabaseFormModel.WebsocketUrl)))
            {
                ShowError("Auth URL and WebSocket URL are required in Server mode.");
                return;
            }

            await ExecuteOperationAsync(
                async () =>
                {
                    var config = DatabaseFormModel.ToConfig();

                    if (DatabaseFormModel.IsEditMode)
                    {
                        await _databaseRepository.UpdateDatabaseConfig(config);
                    }
                    else
                    {
                        await _databaseRepository.AddDittoDatabaseConfig(config);
                    }

                    WeakReferenceMessenger.Default.Send(new HideDatabaseFormMessage());
                },
                errorMessage: "Failed to save database configuration",
                showLoadingState: false,
                showSuccessToast: true,
                successMessage: "Database configuration saved successfully");
        }
        
        public void CancelDatabaseForm()
        {
            DatabaseFormModel.Reset();
        }

        private async Task InitializeAsync()
        {
            await ExecuteOperationAsync(
                async () =>
                {
                    // Set up database config subscriptions and observers
                    await _databaseRepository.SetupDatabaseConfigSubscriptions();

                    // Register observers to update the UI when database configs change
                    _databaseRepository.RegisterLocalObservers(DatabaseConfigs, errorMessage =>
                    {
                        // Handle errors from the observer
                        ShowError(errorMessage);
                    });
                },
                errorMessage: "Failed to initialize database subscriptions",
                showLoadingState: false);
        }

        /// <summary>
        /// Initializes the selected database asynchronously with loading state management
        /// </summary>
        private async Task InitializeSelectedDatabaseAsync(DittoDatabaseConfig config)
        {
            IsInitializingDatabase = true;

            try
            {
                var success = await _dittoManager.InitializeDittoSelectedApp(config);

                if (success && _dittoManager.DittoSelectedApp != null)
                {
                    _logCaptureService.ClearTransportConditionEntries();
                    _logCaptureService.StartCapture(_dittoManager.DittoSelectedApp);
                }

                if (!success)
                {
                    ShowError("Could not initialize database. Please check your configuration and try again.");
                    // Clear selection to stay on database listing view
                    _selectedDatabase = null;
                    OnPropertyChanged(nameof(SelectedDatabase));
                    OnPropertyChanged(nameof(HasSelectedDatabase));
                }
            }
            catch (Exception ex)
            {
                ShowError($"Failed to initialize database: {ex.Message}");
                // Clear selection to stay on database listing view
                _selectedDatabase = null;
                OnPropertyChanged(nameof(SelectedDatabase));
                OnPropertyChanged(nameof(HasSelectedDatabase));
            }
            finally
            {
                IsInitializingDatabase = false;
            }
        }

        /// <summary>
        /// Asynchronously closes the selected database with loading state management
        /// </summary>
        public async Task CloseDatabaseAsync()
        {
            if (_selectedDatabase == null)
                return;

            IsClosingDatabase = true;

            try
            {
                // Stop transport condition observer before closing the database
                _logCaptureService.StopCapture();

                // Close repositories in parallel (they're independent)
                await Task.WhenAll(
                    _systemRepository.CloseDatabaseAsync(),
                    _subscriptionRepository.CloseDatabaseAsync(),
                    _historyRepository.CloseDatabaseAsync(),
                    _favoritesRepository.CloseDatabaseAsync()
                );

                // Close DittoManager last (repositories depend on it)
                await _dittoManager.CloseDatabaseAsync();

                // Clear selection after successful cleanup
                _selectedDatabase = null;
                OnPropertyChanged(nameof(SelectedDatabase));
                OnPropertyChanged(nameof(HasSelectedDatabase));
            }
            catch (Exception ex)
            {
                ShowError($"Error closing database: {ex.Message}");
            }
            finally
            {
                IsClosingDatabase = false;
            }
        }

        [RelayCommand]
        private void OpenDittoPortal()
        {
            const string url = "https://portal.ditto.live";
            try
            {
                if (OperatingSystem.IsWindows())
                    Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
                else if (OperatingSystem.IsMacOS())
                    Process.Start("open", url);
                else
                    Process.Start("xdg-open", url);
            }
            catch (Exception ex)
            {
                ShowError($"Could not open Ditto Portal: {ex.Message}");
            }
        }

        [RelayCommand]
        private async Task ShowQrCodeAsync(DittoDatabaseConfig config)
        {
            if (config == null) return;

            var favorites = await _favoritesRepository.LoadAllQueriesAsync();
            var favQueries = favorites.Select(f => f.Query).ToList();
            var payload = _qrCodeService.Encode(config, favQueries);
            WeakReferenceMessenger.Default.Send(new ShowQrCodeMessage(payload, config.Name));
        }

        [RelayCommand]
        private void ImportFromQrCode()
        {
            WeakReferenceMessenger.Default.Send(new ShowQrCodeImportMessage());
        }


        public void Cleanup()
        {
            // Note: Repositories are singletons managed by DI container
            // They will be disposed automatically when the ServiceProvider is disposed on app exit
            // We don't manually dispose them here since they may be used by other parts of the app

            // If we need to close the current database when the window closes, do it here
            if (SelectedDatabase != null)
            {
                SelectedDatabase = null; // This triggers CloseSelectedDatabase on all repositories
            }
        }
    }
}
