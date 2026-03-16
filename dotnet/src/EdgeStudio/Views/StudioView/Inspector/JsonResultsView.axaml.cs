using Avalonia.Controls;
using Avalonia.Input;
using EdgeStudio.ViewModels;

namespace EdgeStudio.Views.StudioView.Inspector
{
    public partial class JsonResultsView : UserControl
    {
        public JsonResultsView()
        {
            InitializeComponent();
        }

        private void OnCardDoubleTapped(object? sender, TappedEventArgs e)
        {
            if (sender is Button { DataContext: string json } &&
                DataContext is JsonResultsViewModel vm)
            {
                vm.DoubleClickDocumentCommand.Execute(json);
            }
        }
    }
}
