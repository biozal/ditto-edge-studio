using System;
using Avalonia.Controls;
using Avalonia.Interactivity;
using EdgeStudio.ViewModels;

namespace EdgeStudio.Views
{
    public partial class DatabaseFormWindow : Window
    {
        private MainWindowViewModel? _viewModel;
        
        public DatabaseFormWindow()
        {
            InitializeComponent();
            DataContextChanged += OnDataContextChanged;
            Closed += OnWindowClosed;
            
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
            // Unsubscribe from old view model
            if (_viewModel != null)
            {
                _viewModel.HideDatabaseForm -= OnHideDatabaseForm;
            }
            
            // Subscribe to new view model
            _viewModel = DataContext as MainWindowViewModel;
            if (_viewModel != null)
            {
                _viewModel.HideDatabaseForm += OnHideDatabaseForm;
            }
        }
        
        private void OnHideDatabaseForm()
        {
            // Check if the window is still open before trying to close it
            if (IsActive || IsVisible)
            {
                Close();
            }
        }
        
        private void OnWindowClosed(object? sender, EventArgs e)
        {
            // Cleanup event subscriptions when window is closed
            if (_viewModel != null)
            {
                _viewModel.HideDatabaseForm -= OnHideDatabaseForm;
            }
        }
        
        private void Cancel_Click(object? sender, RoutedEventArgs e)
        {
            _viewModel?.CancelDatabaseForm();
            Close();
        }
    }
}