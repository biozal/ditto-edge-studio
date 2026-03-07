using System;
using Avalonia.Controls;
using Avalonia.Interactivity;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Shared.Data.Repositories;
using EdgeStudio.Shared.Messages;
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;
using EdgeStudio.ViewModels;
using Microsoft.Extensions.DependencyInjection;

namespace EdgeStudio.Views
{
    public partial class DatabaseListingView : UserControl,
        IRecipient<ShowAddDatabaseFormMessage>,
        IRecipient<ShowEditDatabaseFormMessage>,
        IRecipient<HideDatabaseFormMessage>,
        IRecipient<ShowQrCodeMessage>,
        IRecipient<ShowQrCodeImportMessage>
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
            WeakReferenceMessenger.Default.Register<ShowQrCodeMessage>(this);
            WeakReferenceMessenger.Default.Register<ShowQrCodeImportMessage>(this);
        }

        private void OnDataContextChanged(object? sender, EventArgs e)
        {
            _viewModel = DataContext as MainWindowViewModel;
        }

        public void Receive(ShowAddDatabaseFormMessage message) => ShowAddDatabaseForm();
        public void Receive(ShowEditDatabaseFormMessage message) => ShowEditDatabaseForm();
        public void Receive(HideDatabaseFormMessage message) => HideDatabaseForm();

        public void Receive(ShowQrCodeMessage message)
        {
            var window = new QrCodeDisplayWindow(message.Payload, message.DatabaseName);
            var mainWindow = TopLevel.GetTopLevel(this) as Window;
            if (mainWindow != null)
                _ = window.ShowDialog(mainWindow);
        }

        public void Receive(ShowQrCodeImportMessage message)
        {
            try
            {
                var sp = App.ServiceProvider;
                var dbRepo = sp?.GetRequiredService<IDatabaseRepository>();
                var favRepo = sp?.GetRequiredService<IFavoritesRepository>();
                var qrService = sp?.GetRequiredService<IQrCodeService>();

                if (dbRepo == null || favRepo == null || qrService == null) return;

                var window = new QrCodeImportWindow(dbRepo, favRepo, qrService);
                var mainWindow = TopLevel.GetTopLevel(this) as Window;
                if (mainWindow != null)
                    _ = window.ShowDialog(mainWindow);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[ERROR] Failed to show QR import window: {ex}");
            }
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
            WeakReferenceMessenger.Default.Unregister<ShowAddDatabaseFormMessage>(this);
            WeakReferenceMessenger.Default.Unregister<ShowEditDatabaseFormMessage>(this);
            WeakReferenceMessenger.Default.Unregister<HideDatabaseFormMessage>(this);
            WeakReferenceMessenger.Default.Unregister<ShowQrCodeMessage>(this);
            WeakReferenceMessenger.Default.Unregister<ShowQrCodeImportMessage>(this);

            base.OnDetachedFromLogicalTree(e);
        }
    }
}
