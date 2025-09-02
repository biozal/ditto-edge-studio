using System;
using Avalonia.Controls;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Messages;
using EdgeStudio.ViewModels;

namespace EdgeStudio.Views.Workspaces;

public partial class SubscriptionListingView : UserControl,
    IRecipient<ShowAddSubscriptionFormMessage>,
    IRecipient<HideSubscriptionFormMessage>
{
    private SubscriptionViewModel? _viewModel;

    public SubscriptionListingView()
    {
        InitializeComponent();
        DataContextChanged += OnDataContextChanged;
        
        // Register for messaging
        WeakReferenceMessenger.Default.Register<ShowAddSubscriptionFormMessage>(this);
        WeakReferenceMessenger.Default.Register<HideSubscriptionFormMessage>(this);
    }
    
    private async void OnDataContextChanged(object? sender, EventArgs e)
    {
        // Update view model reference
        _viewModel = DataContext as SubscriptionViewModel;
        if (_viewModel != null)
        {
            // Load subscriptions when view model is set (this happens when view becomes visible)
            await _viewModel.LoadAsync();
        }
    }
    
    public void Receive(ShowAddSubscriptionFormMessage message)
    {
        ShowAddSubscriptionForm();
    }
    
    public void Receive(HideSubscriptionFormMessage message)
    {
        HideSubscriptionForm();
    }
    
    private async void ShowAddSubscriptionForm()
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
    
    private void HideSubscriptionForm()
    {
        // The form window handles its own closing via the HideSubscriptionForm event
        // This method exists to match the pattern and could be used for cleanup if needed
    }
    
    protected override void OnDetachedFromLogicalTree(Avalonia.LogicalTree.LogicalTreeAttachmentEventArgs e)
    {
        // Unregister from messaging when detached
        WeakReferenceMessenger.Default.Unregister<ShowAddSubscriptionFormMessage>(this);
        WeakReferenceMessenger.Default.Unregister<HideSubscriptionFormMessage>(this);
        
        base.OnDetachedFromLogicalTree(e);
    }
}