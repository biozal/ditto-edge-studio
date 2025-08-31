using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using EdgeStudio.Data;
using EdgeStudio.Data.Repositories;
using EdgeStudio.Models;

namespace EdgeStudio.ViewModels
{
    public partial class MainWindowViewModel : ObservableObject
    {
        private readonly IDatabaseRepository _databaseRepository;
        private readonly IDittoManager _dittoManager;

        public MainWindowViewModel(IDittoManager dittoManager, IDatabaseRepository databaseRepository)
        {
            _databaseRepository = databaseRepository ?? throw new ArgumentNullException(nameof(databaseRepository));
            _dittoManager = dittoManager ?? throw new ArgumentNullException(nameof(dittoManager));
            
            DatabaseConfigs = new ObservableCollection<DittoDatabaseConfig>();
            DatabaseFormModel = new Models.DatabaseFormModel();
            
            // Subscribe to collection changes to update HasDatabaseConfigs
            DatabaseConfigs.CollectionChanged += (s, e) => OnPropertyChanged(nameof(HasDatabaseConfigs));
            
            // Initialize async operations
            _ = InitializeAsync();
        }

        [ObservableProperty]
        private bool isLoading;

        [ObservableProperty]
        private bool isInitializingDatabase;

        [ObservableProperty]
        private string? databaseInitializationError;

        [ObservableProperty]
        private DittoDatabaseConfig? selectedDatabaseConfig;

        private DittoDatabaseConfig? _selectedDatabase;
        
        public DittoDatabaseConfig? SelectedDatabase
        {
            get => _selectedDatabase;
            set
            {
                // Always clear errors when selection changes, regardless of whether value actually changed
                DatabaseInitializationError = null;
                
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
                        _dittoManager.CloseSelectedApp();
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
        public Models.DatabaseFormModel DatabaseFormModel { get; }
        
        /// <summary>
        /// Returns true when there are no database configurations (for empty state visibility)
        /// </summary>
        public bool HasDatabaseConfigs => DatabaseConfigs.Count == 0;
        
        /// <summary>
        /// Event raised when an error occurs
        /// </summary>
        public event EventHandler<string>? ErrorOccurred;
        
        /// <summary>
        /// Event raised when UI needs to show/hide forms
        /// </summary>
        public event Action? ShowAddDatabaseForm;
        public event Action? ShowEditDatabaseForm;
        public event Action? HideDatabaseForm;


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
            ShowAddDatabaseForm?.Invoke();
        }
        
        [RelayCommand]
        private void EditDatabase(DittoDatabaseConfig config)
        {
            if (config == null)
            {
                return;
            }
            
            DatabaseFormModel.LoadFromConfig(config);
            ShowEditDatabaseForm?.Invoke();
        }
        
        [RelayCommand]
        private async Task DeleteDatabaseAsync(DittoDatabaseConfig config)
        {
            try
            {
                if (config == null)
                {
                    ErrorOccurred?.Invoke(this, "Cannot delete: database configuration is null.");
                    return;
                }
                
                await _databaseRepository.DeleteDittoDatabaseConfig(config);
            }
            catch (Exception ex)
            {
                ErrorOccurred?.Invoke(this, $"Failed to delete database configuration: {ex.Message}");
            }
        }
        
        [RelayCommand]
        private async Task SaveDatabaseAsync()
        {
            try
            {
                // Validate required fields
                if (string.IsNullOrWhiteSpace(DatabaseFormModel.Name) ||
                    string.IsNullOrWhiteSpace(DatabaseFormModel.DatabaseId) ||
                    string.IsNullOrWhiteSpace(DatabaseFormModel.AuthToken) ||
                    string.IsNullOrWhiteSpace(DatabaseFormModel.AuthUrl))
                {
                    ErrorOccurred?.Invoke(this, "Please fill in all required fields (marked with *).");
                    return;
                }

                var config = DatabaseFormModel.ToConfig();
                
                if (DatabaseFormModel.IsEditMode)
                {
                    await _databaseRepository.UpdateDatabaseConfig(config);
                }
                else
                {
                    await _databaseRepository.AddDittoDatabaseConfig(config);
                }
                
                HideDatabaseForm?.Invoke();
            }
            catch (Exception ex)
            {
                ErrorOccurred?.Invoke(this, $"Failed to save database configuration: {ex.Message}");
            }
        }
        
        public void CancelDatabaseForm()
        {
            DatabaseFormModel.Reset();
        }

        private async Task InitializeAsync()
        {
            try
            {
                // Set up database config subscriptions and observers
                await _databaseRepository.SetupDatabaseConfigSubscriptions();
                
                // Register observers to update the UI when database configs change
                _databaseRepository.RegisterLocalObservers(DatabaseConfigs, (errorMessage) =>
                {
                    // Handle errors from the observer by raising the ErrorOccurred event
                    ErrorOccurred?.Invoke(this, errorMessage);
                });
            }
            catch (Exception ex)
            {
                ErrorOccurred?.Invoke(this, $"Failed to initialize database subscriptions: {ex.Message}");
            }
        }

        /// <summary>
        /// Initializes the selected database asynchronously with loading state management
        /// </summary>
        private async Task InitializeSelectedDatabaseAsync(DittoDatabaseConfig config)
        {
            try
            {
                IsInitializingDatabase = true;
                
                var success = await _dittoManager.InitializeDittoSelectedApp(config);
                
                if (!success)
                {
                    DatabaseInitializationError = "Could not initialize database. Please check your configuration and try again.";
                    // Clear selection to stay on database listing view
                    _selectedDatabase = null;
                    OnPropertyChanged(nameof(SelectedDatabase));
                    OnPropertyChanged(nameof(HasSelectedDatabase));
                }
            }
            catch (Exception ex)
            {
                DatabaseInitializationError = $"Failed to initialize database: {ex.Message}";
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

        public void Cleanup()
        {
            // Dispose the database repository if it implements IDisposable
            if (_databaseRepository is IDisposable disposable)
            {
                disposable.Dispose();
            }
        }
    }
}
