using System;
using Avalonia.Controls;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Shared.Messages;
using EdgeStudio.ViewModels;
using EdgeStudio.Views.Database;

namespace EdgeStudio.Views.StudioView.Sidebar;

public partial class ObserverListingView : UserControl,
    IRecipient<ShowAddObserverFormMessage>,
    IRecipient<HideObserverFormMessage>
{
    private ObserversViewModel? _viewModel;

    public ObserverListingView()
    {
        InitializeComponent();
        DataContextChanged += OnDataContextChanged;

        // Register for messaging
        WeakReferenceMessenger.Default.Register<ShowAddObserverFormMessage>(this);
        WeakReferenceMessenger.Default.Register<HideObserverFormMessage>(this);
    }

    private async void OnDataContextChanged(object? sender, EventArgs e)
    {
        _viewModel = DataContext as ObserversViewModel;
        if (_viewModel != null)
        {
            try
            {
                await _viewModel.LoadAsync();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[ERROR] Failed to load observers on context change: {ex}");
            }
        }
    }

    public void Receive(ShowAddObserverFormMessage message)
    {
        ShowAddObserverForm();
    }

    public void Receive(HideObserverFormMessage message)
    {
        // The form window handles its own closing via the HideObserverFormMessage
    }

    private async void ShowAddObserverForm()
    {
        if (_viewModel == null) return;

        var window = new ObserverFormWindow();
        window.SetTitle("Add Observer");
        window.DataContext = _viewModel;

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

    protected override void OnDetachedFromLogicalTree(Avalonia.LogicalTree.LogicalTreeAttachmentEventArgs e)
    {
        WeakReferenceMessenger.Default.Unregister<ShowAddObserverFormMessage>(this);
        WeakReferenceMessenger.Default.Unregister<HideObserverFormMessage>(this);

        base.OnDetachedFromLogicalTree(e);
    }
}
