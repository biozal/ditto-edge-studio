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
        private readonly DittoManager _dittoManager;
        private readonly IDatabaseRepository _databaseRepository;

        public MainWindowViewModel(DittoManager dittoManager, IDatabaseRepository databaseRepository)
        {
            _dittoManager = dittoManager ?? throw new ArgumentNullException(nameof(dittoManager));
            _databaseRepository = databaseRepository ?? throw new ArgumentNullException(nameof(databaseRepository));
            
            DatabaseConfigs = new ObservableCollection<DittoDatabaseConfig>();
            
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
        /// Returns true when there are no database configurations (for empty state visibility)
        /// </summary>
        public bool HasDatabaseConfigs => DatabaseConfigs.Count == 0;
        
        /// <summary>
        /// Event raised when an error occurs
        /// </summary>
        public event EventHandler<string>? ErrorOccurred;

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
        private async Task AddDatabaseAsync()
        {
            // TODO: Show dialog to add new database configuration
            // For now, just add a sample config
            var newConfig = new DittoDatabaseConfig(
                Id: Guid.NewGuid().ToString(),
                Name: $"New Database {DatabaseConfigs.Count + 1}",
                DatabaseId: "sample-id",
                AuthToken: "sample-token",
                AuthUrl: "https://example.com",
                HttpApiUrl: "https://api.example.com",
                HttpApiKey: "sample-key",
                Mode: "default",
                AllowUntrustedCerts: false
            );

            await _databaseRepository.AddDittoDatabaseConfig(newConfig);
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
