using System;
using Avalonia.Controls;
using Avalonia.Interactivity;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Messages;
using EdgeStudio.ViewModels;

namespace EdgeStudio.Views
{
    public partial class DatabaseFormWindow : Window, IRecipient<HideDatabaseFormMessage>
    {
        private MainWindowViewModel? _viewModel;
        
        public DatabaseFormWindow()
        {
            InitializeComponent();
            DataContextChanged += OnDataContextChanged;
            Closed += OnWindowClosed;
            
            // Register for messaging
            WeakReferenceMessenger.Default.Register<HideDatabaseFormMessage>(this);
            
            // Handle mode selection toggle buttons
            OnlineToggle.Click += (s, e) => {
                if (OnlineToggle.IsChecked == true)
                {
                    OfflineToggle.IsChecked = false;
                    if (_viewModel != null)
                        _viewModel.DatabaseFormModel.Mode = "online";
                }
            };
            
            OfflineToggle.Click += (s, e) => {
                if (OfflineToggle.IsChecked == true)
                {
                    OnlineToggle.IsChecked = false;
                    if (_viewModel != null)
                        _viewModel.DatabaseFormModel.Mode = "offline";
                }
            };
        }
        
        public void SetTitle(string title)
        {
            Title = title;
            WindowTitle.Text = title;
        }
        
        private void OnDataContextChanged(object? sender, EventArgs e)
        {
            // Update view model reference
            _viewModel = DataContext as MainWindowViewModel;
        }
        
        public void Receive(HideDatabaseFormMessage message)
        {
            // Check if the window is still open before trying to close it
            if (IsActive || IsVisible)
            {
                Close();
            }
        }
        
        private void OnWindowClosed(object? sender, EventArgs e)
        {
            // Unregister from messaging when window is closed
            WeakReferenceMessenger.Default.Unregister<HideDatabaseFormMessage>(this);
        }
        
        private void Cancel_Click(object? sender, RoutedEventArgs e)
        {
            _viewModel?.CancelDatabaseForm();
            Close();
        }
    }
}