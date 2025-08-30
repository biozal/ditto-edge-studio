using EdgeStudio.ViewModels;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;

namespace EdgeStudio
{
    /// <summary>
    /// Interaction logic for MainWindow.xaml
    /// </summary>
    public partial class MainWindow : Window
    {
        private readonly MainWindowViewModel _viewModel;
        
        public MainWindow(MainWindowViewModel viewModel)
        {
            InitializeComponent();
            _viewModel = viewModel ?? throw new ArgumentNullException(nameof(viewModel));
            
            // Set the DataContext to the ViewModel
            DataContext = _viewModel;
            
            // Subscribe to error messages from ViewModel
            _viewModel.ErrorOccurred += OnErrorOccurred;
            
            // Subscribe to form dialog events
            _viewModel.ShowAddDatabaseForm += ShowAddDatabaseForm;
            _viewModel.ShowEditDatabaseForm += ShowEditDatabaseForm;
            _viewModel.HideDatabaseForm += HideDatabaseForm;
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
            _viewModel.CancelDatabaseForm();
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
        
        protected override void OnClosed(EventArgs e)
        {
            // Unsubscribe from error events
            _viewModel.ErrorOccurred -= OnErrorOccurred;
            
            // Unsubscribe from form dialog events
            _viewModel.ShowAddDatabaseForm -= ShowAddDatabaseForm;
            _viewModel.ShowEditDatabaseForm -= ShowEditDatabaseForm;
            _viewModel.HideDatabaseForm -= HideDatabaseForm;
            
            // Clean up the ViewModel when window is closed
            _viewModel.Cleanup();
            base.OnClosed(e);
        }
    }
}