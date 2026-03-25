using Avalonia.Controls;
using Avalonia.Input;
using EdgeStudio.Shared.Models;
using EdgeStudio.ViewModels;

namespace EdgeStudio.Views.StudioView.Inspector
{
    public partial class FavoritesToolView : UserControl
    {
        public FavoritesToolView()
        {
            InitializeComponent();
        }

        private void OnItemDoubleTapped(object? sender, TappedEventArgs e)
        {
            if (sender is Border { DataContext: QueryHistory item } &&
                DataContext is FavoritesToolViewModel vm)
            {
                vm.LoadAndExecuteQueryCommand.Execute(item);
            }
        }
    }
}
