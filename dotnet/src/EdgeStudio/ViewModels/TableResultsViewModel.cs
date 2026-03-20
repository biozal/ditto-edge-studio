using CommunityToolkit.Mvvm.ComponentModel;
using EdgeStudio.Shared.Data;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;

namespace EdgeStudio.ViewModels
{
    /// <summary>
    /// ViewModel for tabular results display with pagination.
    /// </summary>
    public partial class TableResultsViewModel : ObservableObject
    {
        private readonly QueryResultsParser _parser = new();
        private List<TableRow> _allRows = new();

        public ObservableCollection<string> TableHeaders { get; } = new();

        /// <summary>Full row list — used for empty-state detection.</summary>
        public ObservableCollection<TableRow> TableData { get; } = new();

        /// <summary>Current page of rows bound to the DataGrid.</summary>
        public ObservableCollection<TableRow> PagedTableData { get; } = new();

        [ObservableProperty]
        private int _currentPage = 1;

        [ObservableProperty]
        private int _pageSize = 25;

        public event Action<string>? RowSelected;

        /// <summary>Fired when the user double-clicks a row — triggers inspector open + navigate.</summary>
        public event Action<string>? RowDoubleClicked;

        partial void OnCurrentPageChanged(int value) => RefreshPage();

        partial void OnPageSizeChanged(int value)
        {
            CurrentPage = 1;
            RefreshPage();
        }

        public void SetResults(IReadOnlyList<string> jsonDocuments)
        {
            TableHeaders.Clear();
            TableData.Clear();

            var parsed = _parser.Parse(jsonDocuments);

            foreach (var col in parsed.Columns)
                TableHeaders.Add(col);

            _allRows = new List<TableRow>();
            for (var i = 0; i < parsed.Rows.Count; i++)
            {
                var originalJson = i < jsonDocuments.Count ? jsonDocuments[i] : string.Empty;
                var row = new TableRow(parsed.Rows[i], originalJson);
                _allRows.Add(row);
                TableData.Add(row);
            }

            CurrentPage = 1;
            RefreshPage();
        }

        private void RefreshPage()
        {
            PagedTableData.Clear();
            if (_allRows.Count == 0) return;

            var skip = (CurrentPage - 1) * PageSize;
            var take = Math.Min(PageSize, _allRows.Count - skip);
            if (take <= 0) return;

            for (var i = skip; i < skip + take && i < _allRows.Count; i++)
                PagedTableData.Add(_allRows[i]);
        }

        public void Clear()
        {
            TableHeaders.Clear();
            TableData.Clear();
            _allRows.Clear();
            PagedTableData.Clear();
        }

        public void SelectRow(TableRow row)
        {
            RowSelected?.Invoke(row.OriginalJson);
        }

        public void DoubleClickRow(TableRow row)
        {
            RowSelected?.Invoke(row.OriginalJson);
            RowDoubleClicked?.Invoke(row.OriginalJson);
        }
    }

    /// <summary>
    /// Represents a single row in the table results view.
    /// </summary>
    public class TableRow
    {
        public List<string> Cells { get; }
        public string OriginalJson { get; }

        public TableRow(IReadOnlyList<string> cells, string originalJson)
        {
            Cells = cells.ToList();
            OriginalJson = originalJson;
        }
    }
}
