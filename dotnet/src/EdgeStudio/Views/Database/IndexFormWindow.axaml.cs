using System;
using Avalonia.Controls;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Shared.Messages;
using SukiUI.Controls;

namespace EdgeStudio.Views.Database
{
    public partial class IndexFormWindow : SukiWindow, IRecipient<HideIndexFormMessage>
    {
        public IndexFormWindow()
        {
            InitializeComponent();
            Closed += OnWindowClosed;
            WeakReferenceMessenger.Default.Register<HideIndexFormMessage>(this);
        }

        public void Receive(HideIndexFormMessage message)
        {
            if (IsActive || IsVisible)
                Close();
        }

        private void OnWindowClosed(object? sender, EventArgs e)
        {
            WeakReferenceMessenger.Default.Unregister<HideIndexFormMessage>(this);
        }
    }
}
