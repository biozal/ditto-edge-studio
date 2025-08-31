using Avalonia.Controls;
using Avalonia.Interactivity;
using System;

namespace EdgeStudio.Views
{
    public partial class EdgeStudioView : UserControl
    {
        public event EventHandler? CloseRequested;

        public EdgeStudioView()
        {
            InitializeComponent();
        }

        private void CloseButton_Click(object? sender, RoutedEventArgs e)
        {
            // Raise event for parent to handle
            CloseRequested?.Invoke(this, EventArgs.Empty);
        }
    }
}