using System;
using System.ComponentModel;
using Avalonia.Controls;
using Avalonia.Interactivity;
using EdgeStudio.Services;
using EdgeStudio.ViewModels;

namespace EdgeStudio.Views;

public partial class MainWindow : Window
{
    private MainWindowViewModel? _viewModel;
    private EdgeStudioViewModel? _edgeStudioViewModel;

    public MainWindow()
    {
        InitializeComponent();
    }

    public MainWindow(MainWindowViewModel viewModel, EdgeStudioViewModel edgeStudioViewModel) : this()
    {
        _viewModel = viewModel ?? throw new ArgumentNullException(nameof(viewModel));
        _edgeStudioViewModel = edgeStudioViewModel ?? throw new ArgumentNullException(nameof(edgeStudioViewModel));
        
        // Set the DataContext to the main ViewModel
        DataContext = _viewModel;
        
        // Set DataContext for child views
        DatabaseListingView.DataContext = _viewModel;
        EdgeStudioView.DataContext = _edgeStudioViewModel;
        
        // Initialize EdgeStudioViewModel with current database
        _edgeStudioViewModel.SelectedDatabase = _viewModel.SelectedDatabase;
        
        // Subscribe to database selection changes
        _viewModel.PropertyChanged += OnViewModelPropertyChanged;
        
        // Subscribe to close database event from EdgeStudioView
        EdgeStudioView.CloseRequested += OnCloseDatabaseRequested;
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(MainWindowViewModel.SelectedDatabase))
        {
            // Always sync the SelectedDatabase to EdgeStudioViewModel first
            if (_edgeStudioViewModel != null && _viewModel != null)
            {
                _edgeStudioViewModel.SelectedDatabase = _viewModel.SelectedDatabase;
            }
            
            if (_viewModel!.HasSelectedDatabase)
            {
                // Database selection initiated - async initialization will handle the rest
                // Keep showing DatabaseListingView until initialization completes
                DatabaseListingView.IsVisible = true;
                EdgeStudioView.IsVisible = false;
            }
            else
            {
                // No database selected - show database listing
                DatabaseListingView.IsVisible = true;
                EdgeStudioView.IsVisible = false;
            }
        }
        else if (e.PropertyName == nameof(MainWindowViewModel.IsInitializingDatabase))
        {
            // Show/hide loading spinner
            LoadingOverlay.IsVisible = _viewModel!.IsInitializingDatabase;
                
            // If initialization completed successfully and database is selected, show EdgeStudioView
            if (!_viewModel.IsInitializingDatabase && 
                _viewModel.HasSelectedDatabase && 
                string.IsNullOrEmpty(_viewModel.DatabaseInitializationError))
            {
                DatabaseListingView.IsVisible = false;
                EdgeStudioView.IsVisible = true;
            }
        }
        else if (e.PropertyName == nameof(MainWindowViewModel.DatabaseInitializationError))
        {
            // Show/hide error overlay
            ErrorOverlay.IsVisible = !string.IsNullOrEmpty(_viewModel!.DatabaseInitializationError);
        }
    }

    private void OnCloseDatabaseRequested(object? sender, EventArgs e)
    {
        if (_viewModel != null)
        {
            _viewModel.SelectedDatabase = null;
        }
    }
    
    private void DismissError_Click(object? sender, RoutedEventArgs e)
    {
        // Clear the error message to hide the error overlay
        if (_viewModel != null)
        {
            _viewModel.DatabaseInitializationError = null;
        }
    }

    protected override void OnClosed(EventArgs e)
    {
        // Unsubscribe from events
        if (_viewModel != null)
        {
            _viewModel.PropertyChanged -= OnViewModelPropertyChanged;
        }
        
        if (EdgeStudioView != null)
        {
            EdgeStudioView.CloseRequested -= OnCloseDatabaseRequested;
        }
        
        // Clean up the ViewModel when window is closed
        _viewModel?.Cleanup();
        
        base.OnClosed(e);
    }
}