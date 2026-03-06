using CommunityToolkit.Mvvm.ComponentModel;

namespace EdgeStudio.ViewModels
{
    /// <summary>
    /// ViewModel for query explanation results.
    /// </summary>
    public partial class ExplainResultsViewModel : ObservableObject
    {
        [ObservableProperty]
        private string _explainText = string.Empty;

        public void SetResults(string explain)
        {
            ExplainText = explain;
        }

        public void Clear()
        {
            ExplainText = string.Empty;
        }
    }
}
