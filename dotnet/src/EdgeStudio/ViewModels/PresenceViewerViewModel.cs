using EdgeStudio.Shared.Services;

namespace EdgeStudio.ViewModels;

/// <summary>
/// ViewModel for the Presence Viewer tab - to be implemented
/// </summary>
public class PresenceViewerViewModel : ViewModelBase
{
    public string PlaceholderMessage { get; } = "Coming Soon";

    public PresenceViewerViewModel(IToastService? toastService = null)
        : base(toastService)
    {
    }
}
