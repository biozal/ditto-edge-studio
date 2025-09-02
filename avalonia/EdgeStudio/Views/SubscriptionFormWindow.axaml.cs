using System;
using Avalonia.Controls;
using Avalonia.Interactivity;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Messages;
using EdgeStudio.ViewModels;

namespace EdgeStudio.Views
{
    public partial class SubscriptionFormWindow : Window, IRecipient<HideSubscriptionFormMessage>
    {
        private SubscriptionViewModel? _viewModel;
        
        public SubscriptionFormWindow()
        {
            InitializeComponent();
            DataContextChanged += OnDataContextChanged;
            Closed += OnWindowClosed;
            
            // Register for messaging
            WeakReferenceMessenger.Default.Register<HideSubscriptionFormMessage>(this);
        }
        
        public void SetTitle(string title)
        {
            Title = title;
            WindowTitle.Text = title;
        }
        
        private void OnDataContextChanged(object? sender, EventArgs e)
        {
            // Update view model reference
            _viewModel = DataContext as SubscriptionViewModel;
        }
        
        public void Receive(HideSubscriptionFormMessage message)
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
            WeakReferenceMessenger.Default.Unregister<HideSubscriptionFormMessage>(this);
        }
    }
}