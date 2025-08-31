using System;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Layout;
using EdgeStudio.Models;
using EdgeStudio.ViewModels;

namespace EdgeStudio.Views
{
    public partial class DatabaseListingView : UserControl
    {
        private MainWindowViewModel? _viewModel;
        
        public DatabaseListingView()
        {
            InitializeComponent();
            DataContextChanged += OnDataContextChanged;
        }
        
        private void OnDataContextChanged(object? sender, EventArgs e)
        {
            // Unsubscribe from old view model
            if (_viewModel != null)
            {
                _viewModel.ErrorOccurred -= OnErrorOccurred;
                _viewModel.ShowAddDatabaseForm -= ShowAddDatabaseForm;
                _viewModel.ShowEditDatabaseForm -= ShowEditDatabaseForm;
                _viewModel.HideDatabaseForm -= HideDatabaseForm;
            }
            
            // Subscribe to new view model
            _viewModel = DataContext as MainWindowViewModel;
            if (_viewModel != null)
            {
                _viewModel.ErrorOccurred += OnErrorOccurred;
                _viewModel.ShowAddDatabaseForm += ShowAddDatabaseForm;
                _viewModel.ShowEditDatabaseForm += ShowEditDatabaseForm;
                _viewModel.HideDatabaseForm += HideDatabaseForm;
            }
        }
        
        private void OnErrorOccurred(object? sender, string errorMessage)
        {
            // For now, show a simple message box for errors
            // TODO: Replace with Material.Avalonia Snackbar when implementing full Material Design
            ShowErrorMessage("Error", errorMessage);
        }
        
        private async void ShowErrorMessage(string title, string message)
        {
            var parentWindow = TopLevel.GetTopLevel(this) as Window;
            if (parentWindow != null)
            {
                // Create a simple error dialog for now
                var dialog = new Window
                {
                    Title = title,
                    Width = 400,
                    Height = 200,
                    WindowStartupLocation = WindowStartupLocation.CenterOwner,
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
                await dialog.ShowDialog(parentWindow);
            }
        }
        
        public async void ShowAddDatabaseForm()
        {
            var window = new DatabaseFormWindow();
            window.SetTitle("Add Database Configuration");
            window.DataContext = _viewModel;
            
            // Get the main window as owner for proper modal behavior
            var mainWindow = TopLevel.GetTopLevel(this) as Window;
            if (mainWindow != null)
            {
                await window.ShowDialog(mainWindow);
            }
        }
        
        public async void ShowEditDatabaseForm()
        {
            var window = new DatabaseFormWindow();
            window.SetTitle("Edit Database Configuration");
            window.DataContext = _viewModel;
            
            // Get the main window as owner for proper modal behavior
            var mainWindow = TopLevel.GetTopLevel(this) as Window;
            if (mainWindow != null)
            {
                await window.ShowDialog(mainWindow);
            }
        }
        
        public void HideDatabaseForm()
        {
            // Not needed anymore since we're using modal windows that close themselves
        }
        
        private void DatabaseCard_Tapped(object? sender, RoutedEventArgs e)
        {
            if (sender is Border border && border.DataContext is DittoDatabaseConfig config)
            {
                _viewModel?.SelectDatabaseCommand.Execute(config);
            }
        }
    }
}