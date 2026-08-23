using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;

namespace EdgeStudio.ViewModels
{
    /// <summary>
    /// ViewModel for paginated JSON results display.
    /// </summary>
    public partial class JsonResultsViewModel : ObservableObject
    {
        private List<string> _allDocuments = new();

        public ObservableCollection<string> PagedDocuments { get; } = new();

        [ObservableProperty]
        private int _totalCount;

        [ObservableProperty]
        private int _currentPage = 1;

        [ObservableProperty]
        private int _pageSize = 25;

        public ObservableCollection<int> PageSizeOptions { get; } = new() { 25, 50, 100, 250 };

        public int PageCount => Math.Max(1, (int)Math.Ceiling((double)TotalCount / PageSize));

        /// <summary>Fired when the user selects (single-clicks) a document in the results list.</summary>
        public event Action<string>? DocumentSelected;

        /// <summary>Fired when the user double-clicks a document — triggers inspector open + navigate.</summary>
        public event Action<string>? DocumentDoubleClicked;

        /// <summary>Fired when the user requests to add an attachment to a document.</summary>
        public event Action<string>? AddAttachmentRequested;

        /// <summary>Fired when the user requests to delete attachment field(s) from a document.</summary>
        public event Action<string>? DeleteAttachmentRequested;

        partial void OnCurrentPageChanged(int value) => RefreshPage();
        partial void OnPageSizeChanged(int value) { CurrentPage = 1; RefreshPage(); }

        public void SetResults(IReadOnlyList<string> documents)
        {
            _allDocuments = new List<string>(documents);
            TotalCount = documents.Count;
            CurrentPage = 1;
            OnPropertyChanged(nameof(PageCount));
            RefreshPage();
        }

        public void SetError(string message)
        {
            _allDocuments = new List<string> { $"{{\"error\": \"{EscapeJson(message)}\"}}" };
            TotalCount = 0;
            CurrentPage = 1;
            OnPropertyChanged(nameof(PageCount));
            RefreshPage();
        }

        public void Clear()
        {
            _allDocuments.Clear();
            TotalCount = 0;
            CurrentPage = 1;
            OnPropertyChanged(nameof(PageCount));
            RefreshPage();
        }

        [RelayCommand]
        private void SelectDocument(string json)
        {
            DocumentSelected?.Invoke(json);
        }

        [RelayCommand]
        private void DoubleClickDocument(string json)
        {
            DocumentSelected?.Invoke(json);
            DocumentDoubleClicked?.Invoke(json);
        }

        [RelayCommand]
        private void AddAttachment(string json)
        {
            AddAttachmentRequested?.Invoke(json);
        }

        [RelayCommand]
        private void DeleteAttachment(string json)
        {
            DeleteAttachmentRequested?.Invoke(json);
        }

        [RelayCommand]
        private void NextPage()
        {
            if (CurrentPage < PageCount) CurrentPage++;
        }

        [RelayCommand]
        private void PreviousPage()
        {
            if (CurrentPage > 1) CurrentPage--;
        }

        private void RefreshPage()
        {
            PagedDocuments.Clear();
            if (_allDocuments.Count == 0) return;

            var skip = (CurrentPage - 1) * PageSize;
            var take = Math.Min(PageSize, _allDocuments.Count - skip);
            if (take <= 0) return;

            for (var i = skip; i < skip + take && i < _allDocuments.Count; i++)
                PagedDocuments.Add(_allDocuments[i]);
        }

        private static string EscapeJson(string s) =>
            s.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\n", "\\n").Replace("\r", "\\r");
    }
}

