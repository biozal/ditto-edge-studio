using System;
using System.ComponentModel;
using Avalonia.Controls;
using Avalonia.Interactivity;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Messages;
using EdgeStudio.Services;
using EdgeStudio.ViewModels;

namespace EdgeStudio.Views;

public partial class MainWindow : Window, 
    IRecipient<CloseDatabaseRequestedMessage>
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
        
        // Set DataContext for child views BEFORE setting main DataContext
        DatabaseListingView.DataContext = _viewModel;
        EdgeStudioView.DataContext = _edgeStudioViewModel;
        
        // Set the DataContext to the main ViewModel AFTER child contexts are set
        DataContext = _viewModel;
        
        // Don't set EdgeStudioViewModel.SelectedDatabase here - it will be set after initialization completes
        
        // Subscribe to database selection changes
        _viewModel.PropertyChanged += OnViewModelPropertyChanged;
        
        // Subscribe to close database message
        WeakReferenceMessenger.Default.Register<CloseDatabaseRequestedMessage>(this);
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(MainWindowViewModel.SelectedDatabase))
        {
            if (_viewModel!.HasSelectedDatabase)
            {
                // Database selection initiated - async initialization will handle the rest
                // Keep showing DatabaseListingView until initialization completes
                // DO NOT set EdgeStudioViewModel.SelectedDatabase yet - wait for initialization to complete
                DatabaseListingView.IsVisible = true;
                EdgeStudioView.IsVisible = false;
            }
            else
            {
                // No database selected - clear EdgeStudioViewModel and show database listing
                if (_edgeStudioViewModel != null)
                {
                    _edgeStudioViewModel.SelectedDatabase = null;
                }
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
                // NOW it's safe to set the EdgeStudioViewModel database - initialization is complete
                if (_edgeStudioViewModel != null)
                {
                    _edgeStudioViewModel.SelectedDatabase = _viewModel.SelectedDatabase;
                }
                
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

    public void Receive(CloseDatabaseRequestedMessage message)
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
        // Unsubscribe from events and messages
        if (_viewModel != null)
        {
            _viewModel.PropertyChanged -= OnViewModelPropertyChanged;
        }
        
        // Unregister from messaging
        WeakReferenceMessenger.Default.Unregister<CloseDatabaseRequestedMessage>(this);
        
        // Clean up the ViewModel when window is closed
        _viewModel?.Cleanup();
        
        base.OnClosed(e);
    }
}