using Avalonia.Controls;
using Avalonia.Input;
using EdgeStudio.Shared.Models;
using EdgeStudio.ViewModels;

namespace EdgeStudio.Views.StudioView.Inspector
{
    public partial class HistoryToolView : UserControl
    {
        public HistoryToolView()
        {
            InitializeComponent();
        }

        private void OnItemDoubleTapped(object? sender, TappedEventArgs e)
        {
            if (sender is Border { DataContext: QueryHistory item } &&
                DataContext is HistoryToolViewModel vm)
            {
                vm.LoadAndExecuteQueryCommand.Execute(item);
            }
        }
    }
}
