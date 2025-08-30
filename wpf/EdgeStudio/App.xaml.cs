using EdgeStudio.Data;
using EdgeStudio.Data.Repositories;
using EdgeStudio.Helpers;
using EdgeStudio.Models;
using EdgeStudio.Views;
using Microsoft.Extensions.DependencyInjection;
using System.Configuration;
using System.Data;
using System.IO;
using System.Windows;

namespace EdgeStudio
{
    /// <summary>
    /// Interaction logic for App.xaml
    /// </summary>
    public partial class App : Application
    {
        private ServiceProvider? _serviceProvider;
        private LoadingWindow? _loadingWindow;
        
        protected override async void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);
            
            // Apply the current system theme
            var currentTheme = ThemeHelper.GetCurrentTheme();
            ThemeHelper.ApplyTheme(currentTheme);
            
            // Start monitoring for theme changes
            ThemeHelper.StartThemeMonitoring();
            
            // Subscribe to theme change events
            ThemeHelper.ThemeChanged += OnThemeChanged;
            
            // Show loading window
            _loadingWindow = new LoadingWindow();
            _loadingWindow.Show();
            
            try
            {
                // Initialize DI container
                await InitializeDependencyInjectionAsync();
                
                // Create and show main window
                var mainWindow = _serviceProvider!.GetRequiredService<MainWindow>();
                MainWindow = mainWindow;
                mainWindow.Show();
                
                // Close loading window
                _loadingWindow.Close();
            }
            catch (Exception ex)
            {
                _loadingWindow?.Close();
                MessageBox.Show($"Failed to initialize application: {ex.Message}", "Initialization Error", 
                    MessageBoxButton.OK, MessageBoxImage.Error);
                Shutdown();
            }
        }
        
        private async Task InitializeDependencyInjectionAsync()
        {
            // Read .env file from embedded resource
            var envVars = EnvFileReader.Read();
            
            // Create DittoDatabaseConfig from environment variables
            var databaseConfig = new DittoDatabaseConfig(
                Id: Guid.NewGuid().ToString(),
                Name: envVars.GetValueOrDefault("DITTO_NAME", "Local Database"),
                DatabaseId: envVars.GetValueOrDefault("DITTO_DATABASE_ID") ?? throw new InvalidOperationException("DITTO_DATABASE_ID not found in .env"),
                AuthToken: envVars.GetValueOrDefault("DITTO_AUTH_TOKEN") ?? throw new InvalidOperationException("DITTO_AUTH_TOKEN not found in .env"),
                AuthUrl: envVars.GetValueOrDefault("DITTO_AUTH_URL") ?? throw new InvalidOperationException("DITTO_AUTH_URL not found in .env"),
                HttpApiUrl: envVars.GetValueOrDefault("DITTO_HTTP_API_URL", ""),
                HttpApiKey: envVars.GetValueOrDefault("DITTO_HTTP_API_KEY", ""),
                Mode: envVars.GetValueOrDefault("DITTO_MODE", "default"),
                AllowUntrustedCerts: bool.Parse(envVars.GetValueOrDefault("DITTO_ALLOW_UNTRUSTED_CERTS", "false"))
            );
            
            // Initialize DittoManager first (this is critical - must be done before any DI registration)
            var dittoManager = new DittoManager();
            await dittoManager.InitializeDittoAsync(databaseConfig);
            
            // Now set up the DI container with the initialized DittoManager
            var services = new ServiceCollection();
            
            // Register DittoManager as singleton
            services.AddSingleton(dittoManager);
            
            // Register repositories
            services.AddSingleton<IDatabaseRepository, DittoDatabaseRepository>();
            
            // Register ViewModels
            services.AddSingleton<ViewModels.MainWindowViewModel>();
            
            // Register windows
            services.AddSingleton<MainWindow>();
            
            // Build the service provider
            _serviceProvider = services.BuildServiceProvider();
        }
        
        protected override void OnExit(ExitEventArgs e)
        {
            // Clean up theme monitoring
            ThemeHelper.ThemeChanged -= OnThemeChanged;
            ThemeHelper.StopThemeMonitoring();
            
            // Dispose service provider
            _serviceProvider?.Dispose();
            
            base.OnExit(e);
        }
        
        private static void OnThemeChanged(object? sender, ThemeHelper.Theme newTheme)
        {
            // Apply the new theme when the system theme changes
            ThemeHelper.ApplyTheme(newTheme);
        }
    }

}
