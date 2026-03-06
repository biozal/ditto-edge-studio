using CommunityToolkit.Mvvm.ComponentModel;

namespace EdgeStudio.ViewModels
{
    /// <summary>
    /// ViewModel for JSON results display.
    /// </summary>
    public partial class JsonResultsViewModel : ObservableObject
    {
        [ObservableProperty]
        private string _jsonText = string.Empty;

        public void SetResults(string json)
        {
            JsonText = json;
        }

        public void Clear()
        {
            JsonText = string.Empty;
        }
    }
}
