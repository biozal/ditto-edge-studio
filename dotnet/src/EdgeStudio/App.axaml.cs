using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Data.Core.Plugins;
using Avalonia.Layout;
using Avalonia.Markup.Xaml;
using Avalonia.Media;
using CommunityToolkit.Mvvm.Messaging;
using SukiUI;
using SukiUI.Models;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Data.Repositories;
using EdgeStudio.Services;
using EdgeStudio.Shared.Services;
using EdgeStudio.ViewModels;
using EdgeStudio.Views;
using Microsoft.Extensions.DependencyInjection;
using System;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;

namespace EdgeStudio;

public partial class App : Application
{
    private IServiceProvider? _serviceProvider;
    private LoadingWindow? _loadingWindow;

    /// <summary>
    /// Gets the current service provider for dependency injection
    /// </summary>
    public static IServiceProvider? ServiceProvider => (Current as App)?._serviceProvider;

    public override void Initialize()
    {
        AvaloniaXamlLoader.Load(this);

        #if DEBUG
        this.AttachDeveloperTools();
        #endif
    }

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            // Avoid duplicate validations from both Avalonia and the CommunityToolkit.
            // More info: https://docs.avaloniaui.net/docs/guides/development-guides/data-validation#manage-validationplugins
            DisableAvaloniaDataAnnotationValidation();

            // Ensure the theme follows OS setting
            RequestedThemeVariant = Avalonia.Styling.ThemeVariant.Default;

            // Register Ditto brand themes (must happen before any window is shown)
            SetupDittoThemes();

            // Register cleanup handler for application exit
            desktop.Exit += OnApplicationExit;

            // Set loading window as MainWindow - Avalonia will show it via ShowMainWindow()
            _loadingWindow = new LoadingWindow();
            desktop.MainWindow = _loadingWindow;

            // Initialize the application asynchronously
            _ = InitializeApplicationAsync(desktop);
        }

        base.OnFrameworkInitializationCompleted();
    }

    private void OnApplicationExit(object? sender, ControlledApplicationLifetimeExitEventArgs e)
    {
        try
        {
            // Stop Ditto log capture
            var logCapture = _serviceProvider?.GetService<DittoLogCaptureService>();
            logCapture?.Dispose();

            // Dispose logging service
            var loggingService = _serviceProvider?.GetService<ILoggingService>();
            (loggingService as IDisposable)?.Dispose();

            // Dispose DittoManager
            var dittoManager = _serviceProvider?.GetService<IDittoManager>();
            if (dittoManager is IDisposable disposableDitto)
                disposableDitto.Dispose();

            // Dispose local database service
            var localDb = _serviceProvider?.GetService<ILocalDatabaseService>();
            localDb?.Dispose();

            // Dispose ServiceProvider
            if (_serviceProvider is IDisposable serviceProviderDisposable)
                serviceProviderDisposable.Dispose();
        }
        catch
        {
            // Ignore any errors during cleanup
        }
    }

    private async Task InitializeApplicationAsync(IClassicDesktopStyleApplicationLifetime desktop)
    {
        // Yield immediately so OnFrameworkInitializationCompleted() returns and Avalonia can
        // call ShowMainWindow() before we do any work.
        await Task.Yield();

        try
        {
            // Initialize DI container
            await InitializeDependencyInjectionAsync();

            // Create and show the main window
            var mainWindowViewModel = _serviceProvider!.GetRequiredService<MainWindowViewModel>();
            var edgeStudioViewModel = _serviceProvider!.GetRequiredService<EdgeStudioViewModel>();
            var mainWindow = new MainWindow(mainWindowViewModel, edgeStudioViewModel);
            desktop.MainWindow = mainWindow;
            mainWindow.Show();

            // Close the loading window
            _loadingWindow?.Close();
        }
        catch (Exception ex)
        {
            _loadingWindow?.Close();

            await ShowCriticalErrorDialog("Application Startup Error",
                $"Failed to initialize application: {ex.Message}\n\nThe application will now close.");

            desktop.Shutdown();
        }
    }

    private async Task InitializeDependencyInjectionAsync()
    {
        var services = new ServiceCollection();

        // Initialize the local encrypted SQLite database
        var localDatabaseService = new SqliteLocalDatabaseService();
        await localDatabaseService.InitializeAsync();

        // Create logging service first so DittoManager can use it from startup
        var loggingService = new SerilogLoggingService();
        var dittoManager = new DittoManager(loggingService);

        // Register core services
        services.AddSingleton<ILocalDatabaseService>(localDatabaseService);
        services.AddSingleton<IDittoManager>(dittoManager);
        services.AddSingleton<IMessenger>(WeakReferenceMessenger.Default);
        services.AddSingleton<INavigationService, NavigationService>();

        // Register toast service for notifications
        services.AddSingleton<SukiUI.Toasts.ISukiToastManager>(provider =>
        {
            return new SukiUI.Toasts.SukiToastManager();
        });

        // Register dialog service for modal error dialogs
        services.AddSingleton<SukiUI.Dialogs.ISukiDialogManager>(provider =>
        {
            return new SukiUI.Dialogs.SukiDialogManager();
        });
        services.AddSingleton<IDialogService, SukiDialogService>();
        services.AddSingleton<IToastService, SukiToastService>();
        services.AddSingleton<ISyncService, SyncService>();
        services.AddSingleton<IQrCodeService, QrCodeService>();
        services.AddSingleton<INetworkAdapterService, NetworkAdapterService>();

        // Register logging services (use the same instance passed to DittoManager)
        services.AddSingleton<ILoggingService>(loggingService);
        services.AddSingleton<DittoLogCaptureService>();
        services.AddSingleton<ILogCaptureService, LogCaptureService>();

        // Register query execution and metrics services
        services.AddSingleton<IQueryMetricsService, InMemoryQueryMetricsService>();
        services.AddSingleton<IAppMetricsService, AppMetricsService>();
        services.AddSingleton<IQueryService, DittoQueryService>();
        services.AddSingleton<IImportService, ImportService>();

        // Register SQLite-backed repositories
        services.AddSingleton<IDatabaseRepository, SqliteDatabaseRepository>();
        services.AddSingleton<ISubscriptionRepository, SqliteSubscriptionRepository>();
        services.AddSingleton<IHistoryRepository, SqliteHistoryRepository>();
        services.AddSingleton<IFavoritesRepository, SqliteFavoritesRepository>();
        services.AddSingleton<ICollectionsRepository, CollectionsRepository>();
        services.AddSingleton<IObserverRepository, SqliteObserverRepository>();

        // Register settings repository
        var settingsRepo = new SqliteSettingsRepository(localDatabaseService);
        await settingsRepo.InitializeAsync();
        services.AddSingleton<ISettingsRepository>(settingsRepo);

        // Register system repository as singleton
        services.AddSingleton<ISystemRepository, SystemRepository>();
        services.AddSingleton(provider => new Lazy<ISystemRepository>(() => provider.GetRequiredService<ISystemRepository>()));

        // Register ViewModels - Both direct and lazy for DI resolution
        services.AddTransient<PreferencesViewModel>();
        services.AddTransient<MainWindowViewModel>();
        services.AddTransient<EdgeStudioViewModel>();
        services.AddTransient<NavigationViewModel>();
        services.AddTransient<SubscriptionViewModel>();
        services.AddTransient<SubscriptionDetailsViewModel>();
        services.AddTransient<QueryViewModel>();
        services.AddTransient<ObserversViewModel>();
        services.AddTransient<LoggingViewModel>();
        services.AddTransient<AppMetricsViewModel>();
        services.AddTransient<QueryMetricsViewModel>();
        services.AddSingleton<HistoryToolViewModel>();
        services.AddSingleton<FavoritesToolViewModel>();
        services.AddSingleton<IndexesToolViewModel>();
        services.AddTransient<Lazy<NavigationViewModel>>();
        services.AddTransient<Lazy<SubscriptionViewModel>>();
        services.AddTransient<Lazy<SubscriptionDetailsViewModel>>();
        services.AddTransient<Lazy<QueryViewModel>>();
        services.AddTransient<Lazy<ObserversViewModel>>();
        services.AddTransient<Lazy<LoggingViewModel>>();
        services.AddTransient<Lazy<AppMetricsViewModel>>();
        services.AddTransient<Lazy<QueryMetricsViewModel>>();
        services.AddSingleton(provider => new Lazy<HistoryToolViewModel>(() => provider.GetRequiredService<HistoryToolViewModel>()));
        services.AddSingleton(provider => new Lazy<FavoritesToolViewModel>(() => provider.GetRequiredService<FavoritesToolViewModel>()));
        services.AddSingleton(provider => new Lazy<IndexesToolViewModel>(() => provider.GetRequiredService<IndexesToolViewModel>()));

        _serviceProvider = services.BuildServiceProvider();
    }

    private static void SetupDittoThemes()
    {
        var sukiTheme = SukiTheme.GetInstance();

        var dittoYellowTheme = new SukiColorTheme("DittoYellow",
            primary: Color.Parse("#F0D830"),
            accent:  Color.Parse("#2A292A"));

        var dittoDarkTheme = new SukiColorTheme("DittoDark",
            primary: Color.Parse("#2A292A"),
            accent:  Color.Parse("#F0D830"));

        sukiTheme.AddColorTheme(dittoYellowTheme);
        sukiTheme.AddColorTheme(dittoDarkTheme);

        sukiTheme.ChangeColorTheme(dittoDarkTheme);
    }

    private static void DisableAvaloniaDataAnnotationValidation()
    {
        var dataValidationPluginsToRemove =
            BindingPlugins.DataValidators.OfType<DataAnnotationsValidationPlugin>().ToArray();

        foreach (var plugin in dataValidationPluginsToRemove)
        {
            BindingPlugins.DataValidators.Remove(plugin);
        }
    }

    /// <summary>
    /// Shows a critical error dialog when the application cannot continue
    /// </summary>
    private static Task ShowCriticalErrorDialog(string title, string message)
    {
        try
        {
            var dialog = new Window
            {
                Title = title,
                Width = 500,
                Height = 250,
                WindowStartupLocation = WindowStartupLocation.CenterScreen,
                CanResize = false
            };

            var content = new StackPanel
            {
                Margin = new Thickness(20),
                Spacing = 15
            };

            content.Children.Add(new TextBlock
            {
                Text = message,
                TextWrapping = Avalonia.Media.TextWrapping.Wrap,
                FontSize = 16
            });

            var okButton = new Button
            {
                Content = "OK",
                HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center,
                Padding = new Thickness(20, 8)
            };
            okButton.Click += (s, e) => dialog.Close();
            content.Children.Add(okButton);

            dialog.Content = content;
            dialog.Show();
            return Task.CompletedTask;
        }
        catch
        {
            return Task.CompletedTask;
        }
    }

    /// <summary>
    /// Handles the About menu item click event
    /// </summary>
    private void AboutMenuItem_Click(object? sender, EventArgs e)
    {
        var assembly = Assembly.GetExecutingAssembly();
        var version = assembly.GetName().Version?.ToString() ?? "1.0.0";
        var assemblyTitle = assembly.GetCustomAttribute<AssemblyTitleAttribute>()?.Title ?? "Edge Studio";
        var company = assembly.GetCustomAttribute<AssemblyCompanyAttribute>()?.Company ?? "Ditto";
        var copyright = assembly.GetCustomAttribute<AssemblyCopyrightAttribute>()?.Copyright ?? "Copyright © 2025 Ditto";
        var description = assembly.GetCustomAttribute<AssemblyDescriptionAttribute>()?.Description ?? "A powerful database query editor and management tool for Ditto";

        var aboutWindow = new Window
        {
            Title = $"About {assemblyTitle}",
            Width = 450,
            Height = 350,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            CanResize = false,
            Background = new SolidColorBrush(Color.Parse("#1E1E1E"))
        };

        var content = new StackPanel
        {
            Margin = new Thickness(30),
            Spacing = 15,
            HorizontalAlignment = HorizontalAlignment.Center
        };

        content.Children.Add(new TextBlock
        {
            Text = assemblyTitle,
            FontSize = 24,
            FontWeight = FontWeight.Bold,
            Foreground = Brushes.White,
            HorizontalAlignment = HorizontalAlignment.Center
        });

        content.Children.Add(new TextBlock
        {
            Text = $"Version {version}",
            FontSize = 16,
            Foreground = new SolidColorBrush(Color.Parse("#CCCCCC")),
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 0, 0, 10)
        });

        content.Children.Add(new TextBlock
        {
            Text = description,
            FontSize = 14,
            Foreground = new SolidColorBrush(Color.Parse("#AAAAAA")),
            TextWrapping = TextWrapping.Wrap,
            TextAlignment = TextAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center,
            MaxWidth = 380
        });

        content.Children.Add(new Border
        {
            Height = 1,
            Background = new SolidColorBrush(Color.Parse("#333333")),
            Margin = new Thickness(0, 10, 0, 10)
        });

        content.Children.Add(new TextBlock
        {
            Text = company,
            FontSize = 14,
            Foreground = new SolidColorBrush(Color.Parse("#AAAAAA")),
            HorizontalAlignment = HorizontalAlignment.Center
        });

        content.Children.Add(new TextBlock
        {
            Text = copyright,
            FontSize = 14,
            Foreground = new SolidColorBrush(Color.Parse("#888888")),
            HorizontalAlignment = HorizontalAlignment.Center
        });

        var okButton = new Button
        {
            Content = "OK",
            HorizontalAlignment = HorizontalAlignment.Center,
            Padding = new Thickness(30, 8),
            Margin = new Thickness(0, 15, 0, 0),
            MinWidth = 100
        };
        okButton.Click += (s, args) => aboutWindow.Close();
        content.Children.Add(okButton);

        aboutWindow.Content = content;

        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop && desktop.MainWindow != null)
        {
            aboutWindow.ShowDialog(desktop.MainWindow);
        }
        else
        {
            aboutWindow.Show();
        }
    }

    /// <summary>
    /// Handles the Preferences menu item click event (macOS app menu)
    /// </summary>
    private async void PreferencesMenuItem_Click(object? sender, EventArgs e)
    {
        if (_serviceProvider == null) return;

        var vm = _serviceProvider.GetRequiredService<PreferencesViewModel>();
        await vm.LoadSettingsAsync();

        var window = new Views.Settings.PreferencesWindow(vm);

        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop && desktop.MainWindow != null)
            _ = window.ShowDialog(desktop.MainWindow);
        else
            window.Show();
    }
}
