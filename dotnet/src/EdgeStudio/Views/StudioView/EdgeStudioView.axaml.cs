using Avalonia.Controls;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Shared.Messages;
using EdgeStudio.ViewModels;
using EdgeStudio.Views.Database;

namespace EdgeStudio.Views.StudioView
{
    public partial class EdgeStudioView : UserControl, IRecipient<ShowAddIndexFormMessage>
    {
        public EdgeStudioView()
        {
            InitializeComponent();
            WeakReferenceMessenger.Default.Register<ShowAddIndexFormMessage>(this);
        }

        public void Receive(ShowAddIndexFormMessage message)
        {
            ShowIndexForm();
        }

        private async void ShowIndexForm()
        {
            if (DataContext is not EdgeStudioViewModel vm) return;

            // Reset form fields before showing
            vm.IndexesToolViewModel.NewIndexCollection = string.Empty;
            vm.IndexesToolViewModel.NewIndexField = string.Empty;

            var window = new IndexFormWindow
            {
                DataContext = vm.IndexesToolViewModel
            };

            var parentWindow = TopLevel.GetTopLevel(this) as Window;
            if (parentWindow != null)
                await window.ShowDialog(parentWindow);
            else
                window.Show();
        }

        protected override void OnDetachedFromLogicalTree(Avalonia.LogicalTree.LogicalTreeAttachmentEventArgs e)
        {
            WeakReferenceMessenger.Default.Unregister<ShowAddIndexFormMessage>(this);
            base.OnDetachedFromLogicalTree(e);
        }
    }
}
