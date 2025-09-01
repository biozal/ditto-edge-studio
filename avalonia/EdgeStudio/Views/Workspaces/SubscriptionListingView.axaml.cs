using System;
using Avalonia.Controls;
using EdgeStudio.ViewModels;

namespace EdgeStudio.Views.Workspaces;

public partial class SubscriptionListingView : UserControl
{
    private SubscriptionViewModel? _viewModel;

    public SubscriptionListingView()
    {
        InitializeComponent();
        DataContextChanged += OnDataContextChanged;
    }
    
    private async void OnDataContextChanged(object? sender, EventArgs e)
    {
        // Unsubscribe from old view model
        if (_viewModel != null)
        {
            _viewModel.ShowAddSubscriptionForm -= ShowAddSubscriptionForm;
            _viewModel.HideSubscriptionForm -= HideSubscriptionForm;
        }
        
        // Subscribe to new view model
        _viewModel = DataContext as SubscriptionViewModel;
        if (_viewModel != null)
        {
            _viewModel.ShowAddSubscriptionForm += ShowAddSubscriptionForm;
            _viewModel.HideSubscriptionForm += HideSubscriptionForm;
            
            // Load subscriptions when view model is set (this happens when view becomes visible)
            await _viewModel.LoadAsync();
        }
    }
    
    public async void ShowAddSubscriptionForm()
    {
        if (_viewModel == null) return;
        
        var window = new SubscriptionFormWindow();
        window.SetTitle("Add Subscription");
        window.DataContext = _viewModel;
        
        // Get the parent window to center the dialog
        var parentWindow = TopLevel.GetTopLevel(this) as Window;
        if (parentWindow != null)
        {
            await window.ShowDialog(parentWindow);
        }
        else
        {
            window.Show();
        }
    }
    
    public void HideSubscriptionForm()
    {
        // The form window handles its own closing via the HideSubscriptionForm event
        // This method exists to match the pattern and could be used for cleanup if needed
    }
}