using EdgeStudio.ViewModels;
using System;
using System.Windows;
using System.Windows.Controls;

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
        
        private void OnDataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
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
        
        private void ShowSecureField_Click(object sender, RoutedEventArgs e)
        {
            if (sender is Button button && button.Tag is string secureValue)
            {
                // Toggle between masked and actual value
                if (button.Content.ToString() == "***************")
                {
                    button.Content = secureValue;
                    // Hide the value again after 3 seconds
                    var timer = new System.Windows.Threading.DispatcherTimer();
                    timer.Interval = TimeSpan.FromSeconds(3);
                    timer.Tick += (s, args) =>
                    {
                        button.Content = "***************";
                        timer.Stop();
                    };
                    timer.Start();
                }
                else
                {
                    button.Content = "***************";
                }
            }
        }
        
        private void OnErrorOccurred(object? sender, string errorMessage)
        {
            // Show error in popup
            Dispatcher.Invoke(() =>
            {
                ErrorMessageText.Text = errorMessage;
                ErrorPopup.IsOpen = true;
            });
        }
        
        private void CloseErrorPopup_Click(object sender, RoutedEventArgs e)
        {
            ErrorPopup.IsOpen = false;
        }
        
        private void CancelDatabaseForm_Click(object sender, RoutedEventArgs e)
        {
            DatabaseFormPopup.IsOpen = false;
            _viewModel?.CancelDatabaseForm();
        }
        
        public void ShowAddDatabaseForm()
        {
            DatabaseFormTitle.Text = "Add Database Configuration";
            DatabaseFormPopup.IsOpen = true;
        }
        
        public void ShowEditDatabaseForm()
        {
            DatabaseFormTitle.Text = "Edit Database Configuration";
            DatabaseFormPopup.IsOpen = true;
        }
        
        public void HideDatabaseForm()
        {
            DatabaseFormPopup.IsOpen = false;
        }
    }
}