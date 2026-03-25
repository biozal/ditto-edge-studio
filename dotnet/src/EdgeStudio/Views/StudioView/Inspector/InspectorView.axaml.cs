using System.ComponentModel;
using Avalonia.Controls;
using EdgeStudio.ViewModels;

namespace EdgeStudio.Views.StudioView.Inspector;

public partial class InspectorView : UserControl
{
    private EdgeStudioViewModel? _viewModel;

    public InspectorView()
    {
        InitializeComponent();
        DataContextChanged += OnDataContextChanged;
    }

    private void OnDataContextChanged(object? sender, System.EventArgs e)
    {
        if (_viewModel != null)
            _viewModel.PropertyChanged -= OnViewModelPropertyChanged;

        _viewModel = DataContext as EdgeStudioViewModel;

        if (_viewModel != null)
        {
            _viewModel.PropertyChanged += OnViewModelPropertyChanged;
            UpdateMarkdownContent();
            UpdateSubscriptionMarkdownContent();
            UpdateQueryMarkdownContent();
        }
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(EdgeStudioViewModel.LoggingHelpContent))
            UpdateMarkdownContent();
        else if (e.PropertyName == nameof(EdgeStudioViewModel.SubscriptionHelpContent))
            UpdateSubscriptionMarkdownContent();
        else if (e.PropertyName == nameof(EdgeStudioViewModel.QueryHelpContent))
            UpdateQueryMarkdownContent();
    }

    private void UpdateMarkdownContent()
    {
        if (_viewModel != null && !string.IsNullOrEmpty(_viewModel.LoggingHelpContent))
            LoggingHelpContainer.Content = SimpleMarkdownRenderer.Render(_viewModel.LoggingHelpContent);
    }

    private void UpdateSubscriptionMarkdownContent()
    {
        if (_viewModel != null && !string.IsNullOrEmpty(_viewModel.SubscriptionHelpContent))
            SubscriptionHelpContainer.Content = SimpleMarkdownRenderer.Render(_viewModel.SubscriptionHelpContent);
    }

    private void UpdateQueryMarkdownContent()
    {
        if (_viewModel != null && !string.IsNullOrEmpty(_viewModel.QueryHelpContent))
            QueryHelpContainer.Content = SimpleMarkdownRenderer.Render(_viewModel.QueryHelpContent);
    }
}
