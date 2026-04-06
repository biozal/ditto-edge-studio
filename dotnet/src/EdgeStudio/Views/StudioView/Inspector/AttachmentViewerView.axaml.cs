using Avalonia.Controls;
using Avalonia.Interactivity;
using EdgeStudio.Shared.Models;
using EdgeStudio.ViewModels;

namespace EdgeStudio.Views.StudioView.Inspector;

public partial class AttachmentViewerView : UserControl
{
    public AttachmentViewerView()
    {
        InitializeComponent();
    }

    private void OnOpenAttachmentClick(object? sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: AttachmentInfo attachment }
            && DataContext is AttachmentViewModel vm)
        {
            vm.FetchAttachmentCommand.Execute(attachment);
        }
    }
}
