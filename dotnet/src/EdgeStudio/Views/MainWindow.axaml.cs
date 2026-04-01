using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Avalonia.Controls;
using Avalonia.Interactivity;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Shared.Messages;
using EdgeStudio.Shared.Services;
using EdgeStudio.ViewModels;
using SukiUI;
using SukiUI.Controls;
using SukiUI.Enums;
using SukiUI.Models;
using SukiUI.Toasts;

namespace EdgeStudio.Views;

public partial class MainWindow : SukiWindow,
    IRecipient<CloseDatabaseRequestedMessage>
{
    private MainWindowViewModel? _viewModel;
    private EdgeStudioViewModel? _edgeStudioViewModel;

    /// <summary>
    /// Toast manager for displaying notifications
    /// </summary>
    public ISukiToastManager ToastManager { get; }

    /// <summary>
    /// Dialog manager for displaying modal dialogs
    /// </summary>
    public SukiUI.Dialogs.ISukiDialogManager DialogManager { get; }

    public MainWindow()
    {
        // Get the toast manager from the service provider
        ToastManager = App.ServiceProvider?.GetService(typeof(ISukiToastManager)) as ISukiToastManager
            ?? new SukiToastManager();

        // Get the dialog manager from the service provider
        DialogManager = App.ServiceProvider?.GetService(typeof(SukiUI.Dialogs.ISukiDialogManager)) as SukiUI.Dialogs.ISukiDialogManager
            ?? new SukiUI.Dialogs.SukiDialogManager();

        InitializeComponent();
        ConfigurePlatformSpecificStyles();
    }

    private void ConfigurePlatformSpecificStyles()
    {
        // Default to Gradient to match the initial DittoYellow theme.
        // UpdateBackgroundStyle() (called in the ViewModel constructor) will confirm/override
        // once the active theme is known.
        this.BackgroundStyle = SukiBackgroundStyle.Gradient;
    }

    private void UpdateBackgroundStyle(string? themeName)
    {
        BackgroundStyle = themeName == "DittoYellow"
            ? SukiBackgroundStyle.Gradient
            : SukiBackgroundStyle.Flat;
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

        // Sync BackgroundStyle with the active Ditto color theme
        var sukiTheme = SukiTheme.GetInstance();
        sukiTheme.OnColorThemeChanged = theme => UpdateBackgroundStyle(theme.DisplayName);
        UpdateBackgroundStyle(sukiTheme.ActiveColorTheme?.DisplayName);
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
            if (!_viewModel.IsInitializingDatabase && _viewModel.HasSelectedDatabase)
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
    }

    public async void Receive(CloseDatabaseRequestedMessage message)
    {
        try
        {
            if (_viewModel != null)
            {
                await _viewModel.CloseDatabaseAsync();
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[ERROR] Failed to close database: {ex}");
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