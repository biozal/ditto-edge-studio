using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using Avalonia.Controls;
using Avalonia.Data;
using EdgeStudio.ViewModels;

namespace EdgeStudio.Views.StudioView.Inspector
{
    public partial class TableResultsView : UserControl
    {
        private TableResultsViewModel? _viewModel;

        public TableResultsView()
        {
            InitializeComponent();
            DataContextChanged += OnDataContextChanged;
        }

        private void OnDataContextChanged(object? sender, EventArgs e)
        {
            if (_viewModel != null)
            {
                _viewModel.TableHeaders.CollectionChanged -= OnHeadersChanged;
                ResultsGrid.SelectionChanged -= OnSelectionChanged;
            }

            _viewModel = DataContext as TableResultsViewModel;

            if (_viewModel != null)
            {
                _viewModel.TableHeaders.CollectionChanged += OnHeadersChanged;
                ResultsGrid.SelectionChanged += OnSelectionChanged;
                RebuildColumns(_viewModel.TableHeaders);
            }
        }

        private void OnHeadersChanged(object? sender, NotifyCollectionChangedEventArgs e)
        {
            if (_viewModel != null)
                RebuildColumns(_viewModel.TableHeaders);
        }

        private void OnSelectionChanged(object? sender, SelectionChangedEventArgs e)
        {
            if (_viewModel != null && ResultsGrid.SelectedItem is TableRow row)
                _viewModel.SelectRow(row);
        }

        private void OnRowDoubleTapped(object? sender, Avalonia.Input.TappedEventArgs e)
        {
            if (_viewModel != null && ResultsGrid.SelectedItem is TableRow row)
                _viewModel.DoubleClickRow(row);
        }

        private void RebuildColumns(IEnumerable<string> headers)
        {
            ResultsGrid.Columns.Clear();
            var i = 0;
            foreach (var header in headers)
            {
                ResultsGrid.Columns.Add(new DataGridTextColumn
                {
                    Header = header,
                    Binding = new Binding($"Cells[{i}]"),
                    IsReadOnly = true,
                });
                i++;
            }
        }
    }
}
