using EdgeStudio.ViewModels;
using System;
using System.Windows;

namespace EdgeStudio
{
    public partial class MainWindow : Window
    {
        private readonly MainWindowViewModel _viewModel;
        private readonly EdgeStudioViewModel _edgeStudioViewModel;
        
        public MainWindow(MainWindowViewModel viewModel)
        {
            InitializeComponent();
            _viewModel = viewModel ?? throw new ArgumentNullException(nameof(viewModel));
            _edgeStudioViewModel = new EdgeStudioViewModel();
            
            // Set the DataContext to the main ViewModel
            DataContext = _viewModel;
            
            // Set DataContext for child views
            DatabaseListingView.DataContext = _viewModel;
            EdgeStudioView.DataContext = _edgeStudioViewModel;
            
            // Subscribe to database selection changes
            _viewModel.PropertyChanged += OnViewModelPropertyChanged;
            
            // Subscribe to close database event from EdgeStudioView
            EdgeStudioView.CloseRequested += OnCloseDatabaseRequested;
        }
        
        private void OnViewModelPropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
        {
            if (e.PropertyName == nameof(MainWindowViewModel.SelectedDatabase))
            {
                if (_viewModel.HasSelectedDatabase)
                {
                    // Database selection initiated - async initialization will handle the rest
                    // Keep showing DatabaseListingView until initialization completes
                    DatabaseListingView.Visibility = Visibility.Visible;
                    EdgeStudioView.Visibility = Visibility.Collapsed;
                }
                else
                {
                    // No database selected - show database listing
                    DatabaseListingView.Visibility = Visibility.Visible;
                    EdgeStudioView.Visibility = Visibility.Collapsed;
                }
                
                _edgeStudioViewModel.SelectedDatabase = _viewModel.SelectedDatabase;
            }
            else if (e.PropertyName == nameof(MainWindowViewModel.IsInitializingDatabase))
            {
                // Show/hide loading spinner
                LoadingOverlay.Visibility = _viewModel.IsInitializingDatabase 
                    ? Visibility.Visible 
                    : Visibility.Collapsed;
                    
                // If initialization completed successfully and database is selected, show EdgeStudioView
                if (!_viewModel.IsInitializingDatabase && 
                    _viewModel.HasSelectedDatabase && 
                    string.IsNullOrEmpty(_viewModel.DatabaseInitializationError))
                {
                    DatabaseListingView.Visibility = Visibility.Collapsed;
                    EdgeStudioView.Visibility = Visibility.Visible;
                }
            }
            else if (e.PropertyName == nameof(MainWindowViewModel.DatabaseInitializationError))
            {
                // Show/hide error overlay
                ErrorOverlay.Visibility = !string.IsNullOrEmpty(_viewModel.DatabaseInitializationError) 
                    ? Visibility.Visible 
                    : Visibility.Collapsed;
            }
        }
        
        private void OnCloseDatabaseRequested(object? sender, EventArgs e)
        {
            _viewModel.SelectedDatabase = null;
        }
        
        private void DismissError_Click(object sender, RoutedEventArgs e)
        {
            // Clear the error message to hide the error overlay
            _viewModel.DatabaseInitializationError = null;
        }
        
        
        protected override void OnClosed(EventArgs e)
        {
            // Unsubscribe from events
            _viewModel.PropertyChanged -= OnViewModelPropertyChanged;
            EdgeStudioView.CloseRequested -= OnCloseDatabaseRequested;
            
            // Clean up the ViewModel when window is closed
            _viewModel.Cleanup();
            base.OnClosed(e);
        }
    }
}