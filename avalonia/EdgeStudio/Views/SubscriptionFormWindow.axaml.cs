using System;
using Avalonia.Controls;
using Avalonia.Interactivity;
using EdgeStudio.ViewModels;

namespace EdgeStudio.Views
{
    public partial class SubscriptionFormWindow : Window
    {
        private SubscriptionViewModel? _viewModel;
        
        public SubscriptionFormWindow()
        {
            InitializeComponent();
            DataContextChanged += OnDataContextChanged;
            Closed += OnWindowClosed;
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
                _viewModel.HideSubscriptionForm -= OnHideSubscriptionForm;
            }
            
            // Subscribe to new view model
            _viewModel = DataContext as SubscriptionViewModel;
            if (_viewModel != null)
            {
                _viewModel.HideSubscriptionForm += OnHideSubscriptionForm;
            }
        }
        
        private void OnHideSubscriptionForm()
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
                _viewModel.HideSubscriptionForm -= OnHideSubscriptionForm;
            }
        }
    }
}