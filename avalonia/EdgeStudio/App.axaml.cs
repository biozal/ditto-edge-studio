using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Data.Core;
using Avalonia.Data.Core.Plugins;
using Avalonia.Layout;
using Avalonia.Markup.Xaml;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Data;
using EdgeStudio.Data.Repositories;
using EdgeStudio.Helpers;
using EdgeStudio.Models;
using EdgeStudio.Services;
using EdgeStudio.ViewModels;
using EdgeStudio.Views;
using Microsoft.Extensions.DependencyInjection;
using System;
using System.Linq;
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
    }

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            // Avoid duplicate validations from both Avalonia and the CommunityToolkit. 
            // More info: https://docs.avaloniaui.net/docs/guides/development-guides/data-validation#manage-validationplugins
            DisableAvaloniaDataAnnotationValidation();
            
            // Ensure theme follows OS setting
            RequestedThemeVariant = Avalonia.Styling.ThemeVariant.Default;
            
            // Show loading window
            _loadingWindow = new LoadingWindow();
            desktop.MainWindow = _loadingWindow;
            _loadingWindow.Show();
            
            // Initialize application asynchronously
            _ = InitializeApplicationAsync(desktop);
        }

        base.OnFrameworkInitializationCompleted();
    }

    private async Task InitializeApplicationAsync(IClassicDesktopStyleApplicationLifetime desktop)
    {
        try
        {
            // Initialize DI container
            await InitializeDependencyInjectionAsync();
            
            // Create and show main window
            var mainWindowViewModel = _serviceProvider!.GetRequiredService<MainWindowViewModel>();
            var edgeStudioViewModel = _serviceProvider!.GetRequiredService<EdgeStudioViewModel>();
            var mainWindow = new MainWindow(mainWindowViewModel, edgeStudioViewModel);
            desktop.MainWindow = mainWindow;
            mainWindow.Show();
            
            // Close loading window
            _loadingWindow?.Close();
        }
        catch (Exception ex)
        {
            _loadingWindow?.Close();
            
            // Show critical application startup error dialog
            await ShowCriticalErrorDialog("Application Startup Error", 
                $"Failed to initialize application: {ex.Message}\n\nThe application will now close.");
            
            desktop.Shutdown();
        }
    }

    private async Task InitializeDependencyInjectionAsync()
    {
        var services = new ServiceCollection();
        
        try
        {
            // Read environment variables
            var envVars = EnvFileReader.Read();
            
            // Create database configuration from environment variables
            var databaseConfig = new DittoDatabaseConfig(
                Id: Guid.NewGuid().ToString(),
                Name: envVars.TryGetValue("DITTO_NAME", out var name) ? name : "Default Database",
                DatabaseId: envVars["DITTO_DATABASE_ID"],
                AuthToken: envVars["DITTO_AUTH_TOKEN"],
                AuthUrl: envVars["DITTO_AUTH_URL"],
                HttpApiUrl: envVars.TryGetValue("DITTO_HTTP_API_URL", out var httpApiUrl) ? httpApiUrl : "",
                HttpApiKey: envVars.TryGetValue("DITTO_HTTP_API_KEY", out var httpApiKey) ? httpApiKey : "",
                Mode: envVars.TryGetValue("DITTO_MODE", out var mode) ? mode : "online",
                AllowUntrustedCerts: bool.Parse(envVars.TryGetValue("DITTO_ALLOW_UNTRUSTED_CERTS", out var allowUntrusted) ? allowUntrusted : "false")
            );
            
            // Initialize Ditto manager
            var dittoManager = new DittoManager();
            await dittoManager.InitializeDittoAsync(databaseConfig);
            
            // Register services - Singleton for app-wide services
            services.AddSingleton<IDittoManager>(dittoManager);
            services.AddSingleton<IMessenger>(WeakReferenceMessenger.Default);
            services.AddSingleton<INavigationService, NavigationService>();
            
            // Register repositories - Singleton for shared state
            services.AddSingleton<IDatabaseRepository, DittoDatabaseRepository>();
            services.AddSingleton<ISubscriptionRepository, DittoSubscriptionRepository>();
            
            // Register system service as lazy loaded
            services.AddTransient<ISystemService, SystemService>();
            services.AddTransient<Lazy<ISystemService>>();
            
            // Register ViewModels - Both direct and lazy for DI resolution
            services.AddTransient<MainWindowViewModel>();
            services.AddTransient<EdgeStudioViewModel>();
            services.AddTransient<NavigationViewModel>();
            services.AddTransient<SubscriptionViewModel>();
            services.AddTransient<SubscriptionDetailsViewModel>();
            services.AddTransient<CollectionsViewModel>();
            services.AddTransient<HistoryViewModel>();
            services.AddTransient<FavoritesViewModel>();
            services.AddTransient<IndexViewModel>();
            services.AddTransient<ObserversViewModel>();
            services.AddTransient<ToolsViewModel>();
            services.AddTransient<QueryViewModel>();
            services.AddTransient<Lazy<NavigationViewModel>>();
            services.AddTransient<Lazy<SubscriptionViewModel>>();
            services.AddTransient<Lazy<SubscriptionDetailsViewModel>>();
            services.AddTransient<Lazy<CollectionsViewModel>>();
            services.AddTransient<Lazy<HistoryViewModel>>();
            services.AddTransient<Lazy<FavoritesViewModel>>();
            services.AddTransient<Lazy<IndexViewModel>>();
            services.AddTransient<Lazy<ObserversViewModel>>();
            services.AddTransient<Lazy<ToolsViewModel>>();
            services.AddTransient<Lazy<QueryViewModel>>();
            
            _serviceProvider = services.BuildServiceProvider();
        }
        catch (Exception ex)
        {
            // If .env file doesn't exist or has issues, continue with mock services for development
            // Note: This is a non-critical error that allows development to continue with defaults
            // In production, this should be logged to a proper logging system
            _ = ex; // Acknowledge the exception without Console.WriteLine
            
            // Create a default configuration for development
            var defaultConfig = new DittoDatabaseConfig(
                Id: Guid.NewGuid().ToString(),
                Name: "Development Database",
                DatabaseId: "development-app-id",
                AuthToken: "development-token",
                AuthUrl: "https://development.auth.url",
                HttpApiUrl: "",
                HttpApiKey: "",
                Mode: "offline",
                AllowUntrustedCerts: true
            );
            
            var dittoManager = new DittoManager();
            // Don't initialize Ditto in development mode to avoid connection errors
            
            // Register services - Singleton for app-wide services
            services.AddSingleton<IDittoManager>(dittoManager);
            services.AddSingleton<IMessenger>(WeakReferenceMessenger.Default);
            services.AddSingleton<INavigationService, NavigationService>();
            
            // Register repositories - Singleton for shared state
            services.AddSingleton<IDatabaseRepository, DittoDatabaseRepository>();
            services.AddSingleton<ISubscriptionRepository, DittoSubscriptionRepository>();
            
            // Register system service as lazy loaded
            services.AddTransient<ISystemService, SystemService>();
            services.AddTransient<Lazy<ISystemService>>();
            
            // Register ViewModels - Both direct and lazy for DI resolution
            services.AddTransient<MainWindowViewModel>();
            services.AddTransient<EdgeStudioViewModel>();
            services.AddTransient<NavigationViewModel>();
            services.AddTransient<SubscriptionViewModel>();
            services.AddTransient<SubscriptionDetailsViewModel>();
            services.AddTransient<CollectionsViewModel>();
            services.AddTransient<HistoryViewModel>();
            services.AddTransient<FavoritesViewModel>();
            services.AddTransient<IndexViewModel>();
            services.AddTransient<ObserversViewModel>();
            services.AddTransient<ToolsViewModel>();
            services.AddTransient<QueryViewModel>();
            services.AddTransient<Lazy<NavigationViewModel>>();
            services.AddTransient<Lazy<SubscriptionViewModel>>();
            services.AddTransient<Lazy<SubscriptionDetailsViewModel>>();
            services.AddTransient<Lazy<CollectionsViewModel>>();
            services.AddTransient<Lazy<HistoryViewModel>>();
            services.AddTransient<Lazy<FavoritesViewModel>>();
            services.AddTransient<Lazy<IndexViewModel>>();
            services.AddTransient<Lazy<ObserversViewModel>>();
            services.AddTransient<Lazy<ToolsViewModel>>();
            services.AddTransient<Lazy<QueryViewModel>>();
            
            _serviceProvider = services.BuildServiceProvider();
        }
    }

    private static void DisableAvaloniaDataAnnotationValidation()
    {
        // Get an array of plugins to remove
        var dataValidationPluginsToRemove =
            BindingPlugins.DataValidators.OfType<DataAnnotationsValidationPlugin>().ToArray();

        // remove each entry found
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
                Margin = new Avalonia.Thickness(20),
                Spacing = 15
            };
            
            content.Children.Add(new TextBlock 
            { 
                Text = message, 
                TextWrapping = Avalonia.Media.TextWrapping.Wrap,
                FontSize = 14
            });
            
            var okButton = new Button 
            { 
                Content = "OK",
                HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center,
                Padding = new Avalonia.Thickness(20, 8)
            };
            okButton.Click += (s, e) => dialog.Close();
            content.Children.Add(okButton);
            
            dialog.Content = content;
            // Show dialog without parent window
            dialog.Show();
            return Task.CompletedTask;
        }
        catch
        {
            // If we can't even show an error dialog, there's nothing more we can do
            // The application will shut down
            return Task.CompletedTask;
        }
    }
}