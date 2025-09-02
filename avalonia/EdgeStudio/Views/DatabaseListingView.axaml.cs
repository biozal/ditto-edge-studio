using System;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Layout;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Messages;
using EdgeStudio.Models;
using EdgeStudio.ViewModels;

namespace EdgeStudio.Views
{
    public partial class DatabaseListingView : UserControl, 
        IRecipient<ErrorOccurredMessage>,
        IRecipient<ShowAddDatabaseFormMessage>, 
        IRecipient<ShowEditDatabaseFormMessage>,
        IRecipient<HideDatabaseFormMessage>
    {
        private MainWindowViewModel? _viewModel;
        
        public DatabaseListingView()
        {
            InitializeComponent();
            DataContextChanged += OnDataContextChanged;
            
            // Register for messaging
            WeakReferenceMessenger.Default.Register<ErrorOccurredMessage>(this);
            WeakReferenceMessenger.Default.Register<ShowAddDatabaseFormMessage>(this);
            WeakReferenceMessenger.Default.Register<ShowEditDatabaseFormMessage>(this);
            WeakReferenceMessenger.Default.Register<HideDatabaseFormMessage>(this);
        }
        
        private void OnDataContextChanged(object? sender, EventArgs e)
        {
            // Update view model reference
            _viewModel = DataContext as MainWindowViewModel;
        }
        
        public void Receive(ErrorOccurredMessage message)
        {
            // For now, show a simple message box for errors
            // TODO: Replace with Material.Avalonia Snackbar when implementing full Material Design
            ShowErrorMessage("Error", message.ErrorMessage);
        }
        
        public void Receive(ShowAddDatabaseFormMessage message)
        {
            ShowAddDatabaseForm();
        }
        
        public void Receive(ShowEditDatabaseFormMessage message)
        {
            ShowEditDatabaseForm();
        }
        
        public void Receive(HideDatabaseFormMessage message)
        {
            HideDatabaseForm();
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
        
        private async void ShowAddDatabaseForm()
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
        
        private async void ShowEditDatabaseForm()
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
        
        private void HideDatabaseForm()
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
        
        protected override void OnDetachedFromLogicalTree(Avalonia.LogicalTree.LogicalTreeAttachmentEventArgs e)
        {
            // Unregister from messaging when detached
            WeakReferenceMessenger.Default.Unregister<ErrorOccurredMessage>(this);
            WeakReferenceMessenger.Default.Unregister<ShowAddDatabaseFormMessage>(this);
            WeakReferenceMessenger.Default.Unregister<ShowEditDatabaseFormMessage>(this);
            WeakReferenceMessenger.Default.Unregister<HideDatabaseFormMessage>(this);
            
            base.OnDetachedFromLogicalTree(e);
        }
    }
}