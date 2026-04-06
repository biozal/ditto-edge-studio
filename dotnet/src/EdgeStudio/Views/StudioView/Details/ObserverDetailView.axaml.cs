using Avalonia.Controls;
using EdgeStudio.ViewModels;

namespace EdgeStudio.Views.StudioView.Details;

public partial class ObserverDetailView : UserControl
{
    public ObserverDetailView()
    {
        InitializeComponent();
    }

    private void FilterComboBox_SelectionChanged(object? sender, SelectionChangedEventArgs e)
    {
        if (sender is ComboBox comboBox &&
            comboBox.SelectedItem is ComboBoxItem selectedItem &&
            DataContext is ObserversViewModel vm)
        {
            var tag = selectedItem.Tag?.ToString();
            if (!string.IsNullOrEmpty(tag))
            {
                vm.SetEventFilterCommand.Execute(tag);
            }
        }
    }
}
