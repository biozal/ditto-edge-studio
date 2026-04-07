using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Shared.Messages;
using EdgeStudio.Shared.Services;
using EdgeStudio.ViewModels;
using EdgeStudio.Views.Help;

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
        => await OpenSettingsAsync();

    private async Task OpenSettingsAsync()
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

    private async void DownloadQuickstarts_Click(object? sender, EventArgs e)
    {
        var vm = DataContext as MainWindowViewModel;
        try
        {
            var hasDatabase = vm?.SelectedDatabase != null;

            // If no active database connection, warn the user
            if (!hasDatabase)
            {
                var dialogManager = App.ServiceProvider?.GetService(typeof(EdgeStudio.UI.Services.DialogManager))
                    as EdgeStudio.UI.Services.DialogManager;
                if (dialogManager != null)
                {
                    var shouldContinue = await dialogManager.ShowConfirmationAsync(
                        "No Database Connected",
                        "No database is currently connected. Quickstart projects will be downloaded but .env files will not be auto-configured with credentials.\n\nYou can manually configure them later.",
                        "Continue Anyway",
                        "Cancel");
                    if (!shouldContinue) return;
                }
            }

            // Open folder picker
            string? chosenDirectory = await PickFolderAsync();
            if (chosenDirectory == null) return;

            // Check for existing quickstart-main folder
            var service = new QuickstartDownloadService();
            var existingFolder = service.ExistingQuickstartFolder(chosenDirectory);

            while (existingFolder != null)
            {
                var dialogManager = App.ServiceProvider?.GetService(typeof(EdgeStudio.UI.Services.DialogManager))
                    as EdgeStudio.UI.Services.DialogManager;
                if (dialogManager != null)
                {
                    var shouldReplace = await dialogManager.ShowConfirmationAsync(
                        "Folder Already Exists",
                        $"A '{QuickstartDownloadService.ExtractedFolderName}' folder already exists in the selected location.\n\nWould you like to replace it?",
                        "Replace",
                        "Choose Different Location");

                    if (shouldReplace)
                    {
                        service.RemoveExistingFolder(existingFolder);
                        break;
                    }
                    else
                    {
                        chosenDirectory = await PickFolderAsync();
                        if (chosenDirectory == null) return;
                        existingFolder = service.ExistingQuickstartFolder(chosenDirectory);
                        continue;
                    }
                }
                else
                {
                    // No dialog manager available — default to replacing
                    service.RemoveExistingFolder(existingFolder);
                    break;
                }
            }

            // Show progress window
            var progressWindow = new QuickstartProgressWindow();
            progressWindow.Show(this);

            try
            {
                // Download and extract
                var progress = new Progress<string>(msg =>
                    progressWindow.UpdateProgress(msg.Contains("Extracting") ? 50 : 10, msg));
                progressWindow.UpdateProgress(10, "Downloading quickstarts from GitHub...");
                var quickstartDir = await service.DownloadAndExtractAsync(chosenDirectory, progress);

                // Configure if database is connected
                bool isConfigured = false;
                if (hasDatabase && vm?.SelectedDatabase != null)
                {
                    progressWindow.UpdateProgress(60, "Configuring .env files...");
                    var db = vm.SelectedDatabase;
                    service.ConfigureEnvFiles(quickstartDir, db.DatabaseId, db.AuthToken, db.AuthUrl, db.WebsocketUrl);
                    progressWindow.UpdateProgress(80, "Configuring edge-server...");
                    service.ConfigureEdgeServerYaml(quickstartDir, db.DatabaseId, db.AuthToken, db.AuthUrl);
                    isConfigured = true;
                }

                // Discover projects
                progressWindow.UpdateProgress(90, "Discovering projects...");
                var projects = service.DiscoverProjects(quickstartDir, isConfigured);

                // Done — close progress and open browser window
                progressWindow.ShowComplete();
                await Task.Delay(600);
                progressWindow.Close();

                var browserWindow = new QuickstartBrowserWindow(projects, quickstartDir, isConfigured);
                browserWindow.Show();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[ERROR] Download Quickstarts failed: {ex}");
                progressWindow.ShowError(ex.Message);
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[ERROR] Download Quickstarts pre-flight failed: {ex}");
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