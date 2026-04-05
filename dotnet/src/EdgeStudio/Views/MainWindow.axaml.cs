using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Controls.Notifications;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Shared.Messages;
using EdgeStudio.Shared.Services;
using EdgeStudio.ViewModels;
using EdgeStudio.Views.Help;
using SukiUI;
using SukiUI.Controls;
using SukiUI.Dialogs;
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

    private async void Settings_Click(object? sender, EventArgs e)
    {
        var vm = App.ServiceProvider?.GetService(typeof(PreferencesViewModel)) as PreferencesViewModel;
        if (vm == null) return;

        await vm.LoadSettingsAsync();
        var window = new Settings.PreferencesWindow(vm);
        _ = window.ShowDialog(this);
    }

    private void HelpDocumentation_Click(object? sender, EventArgs e)
    {
        var window = new UserGuideWindow();
        window.Show();
    }

    private void VisitDittoWebsite_Click(object? sender, EventArgs e)
    {
        const string url = "https://www.ditto.com/";
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
            System.Diagnostics.Debug.WriteLine($"[ERROR] Could not open Ditto website: {ex.Message}");
        }
    }

    private enum ExistingFolderAction { Replace, ChooseDifferent, Cancel }

    private async void DownloadQuickstarts_Click(object? sender, EventArgs e)
    {
        try
        {
            var vm = DataContext as MainWindowViewModel;
            var hasDatabase = vm?.SelectedDatabase != null;

            // If no active database connection, warn the user
            if (!hasDatabase)
            {
                var tcs = new TaskCompletionSource<bool>();
                var builder = DialogManager.CreateDialog();
                builder.SetType(NotificationType.Warning);
                builder.SetTitle("No Database Connected");
                builder.SetContent(
                    "No database is currently connected. Quickstart projects will be downloaded but .env files will not be auto-configured with credentials.\n\nYou can manually configure them later.");
                builder.AddActionButton("Continue Anyway", _ => tcs.TrySetResult(true), dismissOnClick: true, classes: []);
                builder.AddActionButton("Cancel", _ => tcs.TrySetResult(false), dismissOnClick: true, classes: []);
                builder.TryShow();

                var shouldContinue = await tcs.Task;
                if (!shouldContinue) return;
            }

            // Open folder picker
            string? chosenDirectory = await PickFolderAsync();
            if (chosenDirectory == null) return;

            // Check for existing quickstart-main folder
            var service = new QuickstartDownloadService();
            var existingFolder = service.ExistingQuickstartFolder(chosenDirectory);

            while (existingFolder != null)
            {
                var actionTcs = new TaskCompletionSource<ExistingFolderAction>();
                var existingBuilder = DialogManager.CreateDialog();
                existingBuilder.SetType(NotificationType.Warning);
                existingBuilder.SetTitle("Folder Already Exists");
                existingBuilder.SetContent(
                    $"A '{QuickstartDownloadService.ExtractedFolderName}' folder already exists in the selected location.\n\nWhat would you like to do?");
                existingBuilder.AddActionButton("Replace", _ => actionTcs.TrySetResult(ExistingFolderAction.Replace), dismissOnClick: true, classes: []);
                existingBuilder.AddActionButton("Choose Different Location", _ => actionTcs.TrySetResult(ExistingFolderAction.ChooseDifferent), dismissOnClick: true, classes: []);
                existingBuilder.AddActionButton("Cancel", _ => actionTcs.TrySetResult(ExistingFolderAction.Cancel), dismissOnClick: true, classes: []);
                existingBuilder.TryShow();

                var action = await actionTcs.Task;
                if (action == ExistingFolderAction.Cancel) return;

                if (action == ExistingFolderAction.Replace)
                {
                    service.RemoveExistingFolder(existingFolder);
                    break;
                }

                // ChooseDifferent — re-open the folder picker
                chosenDirectory = await PickFolderAsync();
                if (chosenDirectory == null) return;
                existingFolder = service.ExistingQuickstartFolder(chosenDirectory);
            }

            // Download and extract
            var quickstartDir = await service.DownloadAndExtractAsync(chosenDirectory);

            // Configure if database is connected
            bool isConfigured = false;
            if (hasDatabase && vm?.SelectedDatabase != null)
            {
                var db = vm.SelectedDatabase;
                service.ConfigureEnvFiles(quickstartDir, db.DatabaseId, db.AuthToken, db.AuthUrl, db.WebsocketUrl);
                service.ConfigureEdgeServerYaml(quickstartDir, db.DatabaseId, db.AuthToken, db.AuthUrl);
                isConfigured = true;
            }

            // Discover projects and open browser window
            var projects = service.DiscoverProjects(quickstartDir, isConfigured);
            var browserWindow = new QuickstartBrowserWindow(projects, quickstartDir, isConfigured);
            browserWindow.Show();
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[ERROR] Download Quickstarts failed: {ex}");
            var errorBuilder = DialogManager.CreateDialog();
            errorBuilder.SetType(NotificationType.Error);
            errorBuilder.SetTitle("Download Failed");
            errorBuilder.SetContent($"Failed to download quickstarts: {ex.Message}");
            errorBuilder.AddActionButton("OK", _ => { }, dismissOnClick: true, classes: []);
            errorBuilder.TryShow();
        }
    }

    private async Task<string?> PickFolderAsync()
    {
        var folders = await StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions
        {
            Title = "Choose a folder to download the Ditto Quickstarts into",
            AllowMultiple = false
        });

        var folder = folders.FirstOrDefault();
        return folder?.TryGetLocalPath();
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