using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using EdgeStudio.Data;
using EdgeStudio.Data.Repositories;
using EdgeStudio.Models;
using System.Collections.ObjectModel;

namespace EdgeStudio.ViewModels
{
    public partial class MainWindowViewModel : ObservableObject
    {
        private readonly IDittoManager _dittoManager;
        private readonly IDatabaseRepository _databaseRepository;

        public MainWindowViewModel(IDittoManager dittoManager, IDatabaseRepository databaseRepository)
        {
            _dittoManager = dittoManager ?? throw new ArgumentNullException(nameof(dittoManager));
            _databaseRepository = databaseRepository ?? throw new ArgumentNullException(nameof(databaseRepository));
            
            DatabaseConfigs = new ObservableCollection<DittoDatabaseConfig>();
            DatabaseFormModel = new Models.DatabaseFormModel();
            
            // Subscribe to collection changes to update HasDatabaseConfigs
            DatabaseConfigs.CollectionChanged += (s, e) => OnPropertyChanged(nameof(HasDatabaseConfigs));
            
            // Initialize async operations
            _ = InitializeAsync();
        }

        [ObservableProperty]
        private string queryText = "SELECT * FROM collection";

        [ObservableProperty]
        private string queryResults = "Query results will appear here...";

        [ObservableProperty]
        private bool isLoading;

        [ObservableProperty]
        private DittoDatabaseConfig? selectedDatabaseConfig;

        public ObservableCollection<DittoDatabaseConfig> DatabaseConfigs { get; }
        
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
        private async Task ExecuteQueryAsync()
        {
            if (string.IsNullOrWhiteSpace(QueryText))
                return;

            try
            {
                IsLoading = true;
                
                // TODO: Implement actual query execution using DittoManager
                // For now, just simulate a query execution
                await Task.Delay(500); // Simulate async work
                QueryResults = $"Query executed: {QueryText}\nTimestamp: {DateTime.Now:yyyy-MM-dd HH:mm:ss}";
            }
            catch (Exception ex)
            {
                QueryResults = $"Error executing query: {ex.Message}";
            }
            finally
            {
                IsLoading = false;
            }
        }

        [RelayCommand]
        private void ClearQuery()
        {
            QueryText = string.Empty;
            QueryResults = "Query results will appear here...";
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
            DatabaseFormModel.LoadFromConfig(config);
            ShowEditDatabaseForm?.Invoke();
        }
        
        [RelayCommand]
        private async Task DeleteDatabaseAsync(DittoDatabaseConfig config)
        {
            try
            {
                System.Diagnostics.Debug.WriteLine($"[DEBUG] DeleteDatabaseAsync called for database: {config?.Name} (ID: {config?.Id})");
                
                if (config == null)
                {
                    System.Diagnostics.Debug.WriteLine("[DEBUG] DeleteDatabaseAsync: config is null!");
                    ErrorOccurred?.Invoke(this, "Cannot delete: database configuration is null.");
                    return;
                }

                System.Diagnostics.Debug.WriteLine($"[DEBUG] DatabaseConfigs count before delete: {DatabaseConfigs.Count}");
                
                await _databaseRepository.DeleteDittoDatabaseConfig(config);
                
                System.Diagnostics.Debug.WriteLine("[DEBUG] DeleteDittoDatabaseConfig completed successfully");
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DEBUG] DeleteDatabaseAsync exception: {ex.Message}");
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
