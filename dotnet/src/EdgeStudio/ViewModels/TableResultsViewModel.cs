using CommunityToolkit.Mvvm.ComponentModel;
using System.Collections.ObjectModel;

namespace EdgeStudio.ViewModels
{
    /// <summary>
    /// ViewModel for tabular results display.
    /// </summary>
    public partial class TableResultsViewModel : ObservableObject
    {
        public ObservableCollection<ObservableCollection<string>> TableData { get; } = new();
        public ObservableCollection<string> TableHeaders { get; } = new();

        public void SetResults(ObservableCollection<string> headers, ObservableCollection<ObservableCollection<string>> data)
        {
            TableHeaders.Clear();
            foreach (var header in headers)
            {
                TableHeaders.Add(header);
            }

            TableData.Clear();
            foreach (var row in data)
            {
                TableData.Add(row);
            }
        }

        public void Clear()
        {
            TableHeaders.Clear();
            TableData.Clear();
        }
    }
}
