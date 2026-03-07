using EdgeStudio.Shared.Services;

namespace EdgeStudio.ViewModels;

/// <summary>
/// Placeholder ViewModel for App Metrics. Full implementation planned.
/// </summary>
public partial class AppMetricsViewModel : LoadableViewModelBase
{
    public AppMetricsViewModel(IToastService? toastService = null) : base(toastService)
    {
    }
}
