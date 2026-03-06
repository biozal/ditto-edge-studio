using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using System;
using System.Threading.Tasks;

namespace EdgeStudio.ViewModels
{
    /// <summary>
    /// ViewModel for a single query editor tab.
    /// </summary>
    public partial class QueryDocumentViewModel : ObservableObject
    {
        public string Id { get; private set; } = string.Empty;

        [ObservableProperty]
        private string _title = string.Empty;

        private string _queryText = string.Empty;
        private bool _isDirty = false;
        private string _originalQueryText = string.Empty;
        private readonly JsonResultsViewModel? _jsonResults;
        private readonly TableResultsViewModel? _tableResults;
        private readonly ExplainResultsViewModel? _explainResults;

        public string QueryText
        {
            get => _queryText;
            set
            {
                if (SetProperty(ref _queryText, value))
                {
                    UpdateDirtyState();
                }
            }
        }

        public bool IsDirty
        {
            get => _isDirty;
            private set
            {
                if (SetProperty(ref _isDirty, value))
                {
                    UpdateTitle();
                }
            }
        }

        private string _baseTitle = "New Query";

        public QueryDocumentViewModel()
        {
            Id = Guid.NewGuid().ToString();
            _baseTitle = "New Query";
            Title = _baseTitle;
        }

        public QueryDocumentViewModel(string title, JsonResultsViewModel? jsonResults, TableResultsViewModel? tableResults, ExplainResultsViewModel? explainResults, string queryText = "")
        {
            Id = Guid.NewGuid().ToString();
            _baseTitle = title;
            Title = title;
            _queryText = queryText;
            _originalQueryText = queryText;
            _jsonResults = jsonResults;
            _tableResults = tableResults;
            _explainResults = explainResults;
        }

        private void UpdateDirtyState()
        {
            IsDirty = _queryText != _originalQueryText;
        }

        private void UpdateTitle()
        {
            Title = IsDirty ? $"{_baseTitle}*" : _baseTitle;
        }

        [RelayCommand]
        private async Task ExecuteQuery()
        {
            // Placeholder for query execution
            await Task.Delay(100);

            if (_jsonResults != null && !string.IsNullOrWhiteSpace(QueryText))
            {
                // Sample JSON results
                var sampleJson = @"{
  ""query"": """ + QueryText.Replace("\"", "\\\"") + @""",
  ""results"": [
    {
      ""_id"": ""1"",
      ""name"": ""Sample Document 1"",
      ""value"": 42
    },
    {
      ""_id"": ""2"",
      ""name"": ""Sample Document 2"",
      ""value"": 123
    }
  ],
  ""count"": 2
}";

                _jsonResults.SetResults(sampleJson);
            }
        }

        [RelayCommand]
        private void SaveQuery()
        {
            // Save the query text (mark as clean)
            _originalQueryText = _queryText;
            IsDirty = false;
        }

        /// <summary>
        /// Called before the document is closed. Returns true if close should proceed.
        /// </summary>
        public bool CanClose()
        {
            // If not dirty, can close immediately
            if (!IsDirty)
            {
                return true;
            }

            // TODO: Show confirmation dialog
            // For now, allow closing without confirmation
            return true;
        }
    }
}
