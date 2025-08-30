using EdgeStudio.Data;
using EdgeStudio.Data.Repositories;
using System.Windows;

namespace EdgeStudio
{
    /// <summary>
    /// Interaction logic for MainWindow.xaml
    /// </summary>
    public partial class MainWindow : Window
    {
        private readonly DittoManager _dittoManager;
        private readonly IDatabaseRepository _databaseRepository;
        
        public MainWindow(DittoManager dittoManager, IDatabaseRepository databaseRepository)
        {
            InitializeComponent();
            _dittoManager = dittoManager;
            _databaseRepository = databaseRepository;
            
            // Initialize any UI components that need the services
            Loaded += OnMainWindowLoaded;
        }
        
        private async void OnMainWindowLoaded(object sender, RoutedEventArgs e)
        {
            // Set up database config subscriptions after window is loaded
            try
            {
                await _databaseRepository.SetupDatabaseConfigSubscriptions();
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to set up database subscriptions: {ex.Message}", 
                    "Initialization Error", MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        }
    }
}