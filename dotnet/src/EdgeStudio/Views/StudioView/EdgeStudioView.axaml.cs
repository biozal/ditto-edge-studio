using System.ComponentModel;
using Avalonia;
using Avalonia.Controls;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Shared.Messages;
using EdgeStudio.ViewModels;
using EdgeStudio.Views.Database;

namespace EdgeStudio.Views.StudioView
{
    public partial class EdgeStudioView : UserControl, IRecipient<ShowAddIndexFormMessage>
    {
        private EdgeStudioViewModel? _viewModel;
        private GridLength _savedInspectorWidth = new(280);

        public EdgeStudioView()
        {
            InitializeComponent();
            WeakReferenceMessenger.Default.Register<ShowAddIndexFormMessage>(this);
            DataContextChanged += OnDataContextChanged;
        }

        private void OnDataContextChanged(object? sender, System.EventArgs e)
        {
            // Unsubscribe from old ViewModel
            if (_viewModel != null)
                _viewModel.PropertyChanged -= OnViewModelPropertyChanged;

            _viewModel = DataContext as EdgeStudioViewModel;

            if (_viewModel != null)
            {
                _viewModel.PropertyChanged += OnViewModelPropertyChanged;
                UpdateInspectorColumn(_viewModel.IsInspectorVisible);
            }
        }

        private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
        {
            if (e.PropertyName == nameof(EdgeStudioViewModel.IsInspectorVisible) && _viewModel != null)
                UpdateInspectorColumn(_viewModel.IsInspectorVisible);
        }

        private void UpdateInspectorColumn(bool isVisible)
        {
            var inspectorCol = MainLayoutGrid.ColumnDefinitions[6];
            var splitterCol = MainLayoutGrid.ColumnDefinitions[5];

            if (isVisible)
            {
                inspectorCol.Width = _savedInspectorWidth;
                inspectorCol.MinWidth = 200;
                splitterCol.Width = GridLength.Auto;
            }
            else
            {
                // Save current width before collapsing
                _savedInspectorWidth = inspectorCol.Width;
                inspectorCol.Width = new GridLength(0);
                inspectorCol.MinWidth = 0;
                splitterCol.Width = new GridLength(0);
            }
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
            if (_viewModel != null)
                _viewModel.PropertyChanged -= OnViewModelPropertyChanged;
            base.OnDetachedFromLogicalTree(e);
        }
    }
}
