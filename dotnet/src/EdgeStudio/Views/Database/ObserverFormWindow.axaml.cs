using System;
using Avalonia.Controls;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Shared.Messages;
using EdgeStudio.ViewModels;
using SukiUI.Controls;

namespace EdgeStudio.Views.Database
{
    public partial class ObserverFormWindow : SukiWindow, IRecipient<HideObserverFormMessage>
    {
        private ObserversViewModel? _viewModel;

        public ObserverFormWindow()
        {
            InitializeComponent();
            DataContextChanged += OnDataContextChanged;
            Closed += OnWindowClosed;

            // Register for messaging
            WeakReferenceMessenger.Default.Register<HideObserverFormMessage>(this);
        }

        public void SetTitle(string title)
        {
            Title = title;
            WindowTitle.Text = title;
        }

        private void OnDataContextChanged(object? sender, EventArgs e)
        {
            _viewModel = DataContext as ObserversViewModel;
        }

        public void Receive(HideObserverFormMessage message)
        {
            if (IsActive || IsVisible)
            {
                Close();
            }
        }

        private void OnWindowClosed(object? sender, EventArgs e)
        {
            WeakReferenceMessenger.Default.Unregister<HideObserverFormMessage>(this);
        }
    }
}
