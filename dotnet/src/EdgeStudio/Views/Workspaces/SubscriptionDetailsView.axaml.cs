using Avalonia.Controls;
using Avalonia.Interactivity;
using EdgeStudio.ViewModels;

namespace EdgeStudio.Views.Workspaces;

public partial class SubscriptionDetailsView : UserControl
{
    public SubscriptionDetailsView()
    {
        InitializeComponent();
    }

    private async void TransportSettingsButton_Click(object sender, RoutedEventArgs e)
    {
        var vm = (SubscriptionDetailsViewModel)DataContext!;
        var window = new TransportSettingsWindow(vm.Settings);
        var owner = TopLevel.GetTopLevel(this) as Window;
        if (owner != null)
            await window.ShowDialog(owner);
    }
}
