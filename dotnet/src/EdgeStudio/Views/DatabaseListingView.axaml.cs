using System;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Layout;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Shared.Messages;
using EdgeStudio.Shared.Models;
using EdgeStudio.ViewModels;

namespace EdgeStudio.Views
{
    public partial class DatabaseListingView : UserControl,
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
            WeakReferenceMessenger.Default.Register<ShowAddDatabaseFormMessage>(this);
            WeakReferenceMessenger.Default.Register<ShowEditDatabaseFormMessage>(this);
            WeakReferenceMessenger.Default.Register<HideDatabaseFormMessage>(this);
        }
        
        private void OnDataContextChanged(object? sender, EventArgs e)
        {
            // Update view model reference
            _viewModel = DataContext as MainWindowViewModel;
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

        private async void ShowAddDatabaseForm()
        {
            try
            {
                var window = new DatabaseFormWindow();
                window.SetTitle("Add Database Configuration");
                window.DataContext = _viewModel;

                var mainWindow = TopLevel.GetTopLevel(this) as Window;
                if (mainWindow != null)
                {
                    await window.ShowDialog(mainWindow);
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[ERROR] Failed to show add database form: {ex}");
            }
        }

        private async void ShowEditDatabaseForm()
        {
            try
            {
                var window = new DatabaseFormWindow();
                window.SetTitle("Edit Database Configuration");
                window.DataContext = _viewModel;

                var mainWindow = TopLevel.GetTopLevel(this) as Window;
                if (mainWindow != null)
                {
                    await window.ShowDialog(mainWindow);
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[ERROR] Failed to show edit database form: {ex}");
            }
        }
        
        private void HideDatabaseForm()
        {
            // Not needed anymore since we're using modal windows that close themselves
        }
        
        private void DatabaseCard_Tapped(object? sender, RoutedEventArgs e)
        {
            // Ignore taps that originated from a Button (Edit / Delete)
            if (e.Source is Button) return;

            if (sender is Control control && control.DataContext is DittoDatabaseConfig config)
            {
                _viewModel?.SelectDatabaseCommand.Execute(config);
            }
        }
        
        protected override void OnDetachedFromLogicalTree(Avalonia.LogicalTree.LogicalTreeAttachmentEventArgs e)
        {
            // Unregister from messaging when detached
            WeakReferenceMessenger.Default.Unregister<ShowAddDatabaseFormMessage>(this);
            WeakReferenceMessenger.Default.Unregister<ShowEditDatabaseFormMessage>(this);
            WeakReferenceMessenger.Default.Unregister<HideDatabaseFormMessage>(this);

            base.OnDetachedFromLogicalTree(e);
        }
    }
}