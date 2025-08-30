using Microsoft.Win32;
using System.Management;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Windows;
using System.Windows.Media;

namespace EdgeStudio.Helpers
{
    public static class ThemeHelper
    {
        private static ManagementEventWatcher? _themeWatcher;
        
        // Registry key for Windows theme settings
        private const string RegistryKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";
        private const string RegistryValueName = "AppsUseLightTheme";
        
        public enum Theme
        {
            Light,
            Dark
        }
        
        public static event EventHandler<Theme>? ThemeChanged;
        
        /// <summary>
        /// Gets the current Windows theme
        /// </summary>
        public static Theme GetCurrentTheme()
        {
            try
            {
                using (RegistryKey? key = Registry.CurrentUser.OpenSubKey(RegistryKeyPath))
                {
                    object? registryValueObject = key?.GetValue(RegistryValueName);
                    if (registryValueObject != null)
                    {
                        int registryValue = (int)registryValueObject;
                        return registryValue > 0 ? Theme.Light : Theme.Dark;
                    }
                }
            }
            catch
            {
                // Fall back to light theme if we can't read the registry
            }
            
            return Theme.Light;
        }
        
        /// <summary>
        /// Starts monitoring for theme changes
        /// </summary>
        public static void StartThemeMonitoring()
        {
            try
            {
                // Use WMI to monitor registry changes
                var currentUser = WindowsIdentity.GetCurrent();
                var query = new WqlEventQuery(
                    "SELECT * FROM RegistryValueChangeEvent WHERE " +
                    $@"Hive='HKEY_CURRENT_USER' AND " +
                    $@"KeyPath='{RegistryKeyPath.Replace(@"\", @"\\")}' AND " +
                    $@"ValueName='{RegistryValueName}'");
                
                _themeWatcher = new ManagementEventWatcher(query);
                _themeWatcher.EventArrived += OnThemeRegistryChanged;
                _themeWatcher.Start();
            }
            catch
            {
                // If WMI monitoring fails, we can fall back to polling or just ignore
                // Some systems might have WMI disabled
            }
            
            // Alternative: Use SystemEvents which is simpler but less precise
            SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
        }
        
        /// <summary>
        /// Stops monitoring for theme changes
        /// </summary>
        public static void StopThemeMonitoring()
        {
            _themeWatcher?.Stop();
            _themeWatcher?.Dispose();
            _themeWatcher = null;
            
            SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
        }
        
        private static void OnThemeRegistryChanged(object sender, EventArrivedEventArgs e)
        {
            Application.Current?.Dispatcher.Invoke(() =>
            {
                var newTheme = GetCurrentTheme();
                ThemeChanged?.Invoke(null, newTheme);
            });
        }
        
        private static void OnUserPreferenceChanged(object sender, UserPreferenceChangedEventArgs e)
        {
            if (e.Category == UserPreferenceCategory.General || e.Category == UserPreferenceCategory.Color)
            {
                Application.Current?.Dispatcher.Invoke(() =>
                {
                    var newTheme = GetCurrentTheme();
                    ThemeChanged?.Invoke(null, newTheme);
                });
            }
        }
        
        /// <summary>
        /// Applies the specified theme to the application
        /// </summary>
        public static void ApplyTheme(Theme theme)
        {
            var app = Application.Current;
            if (app == null) return;
            
            var themeDict = new ResourceDictionary();
            string themeName = theme == Theme.Dark ? "DarkTheme" : "LightTheme";
            themeDict.Source = new Uri($"pack://application:,,,/Themes/{themeName}.xaml");
            
            // Remove existing theme dictionaries
            var existingTheme = app.Resources.MergedDictionaries
                .FirstOrDefault(d => d.Source?.ToString().Contains("/Themes/") == true);
            
            if (existingTheme != null)
            {
                app.Resources.MergedDictionaries.Remove(existingTheme);
            }
            
            // Add new theme dictionary
            app.Resources.MergedDictionaries.Add(themeDict);
        }
    }
}