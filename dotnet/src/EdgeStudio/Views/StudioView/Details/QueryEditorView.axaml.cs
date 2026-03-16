using Avalonia.Controls;
using AvaloniaEdit.TextMate;
using EdgeStudio.ViewModels;
using System;
using System.ComponentModel;
using TextMateSharp.Grammars;

namespace EdgeStudio.Views.StudioView.Details
{
    public partial class QueryEditorView : UserControl
    {
        private bool _isUpdatingText;
        private QueryDocumentViewModel? _currentViewModel;
        private PropertyChangedEventHandler? _propertyChangedHandler;

        public QueryEditorView()
        {
            InitializeComponent();
            SetupSyntaxHighlighting();
            DataContextChanged += OnDataContextChanged;
            QueryEditor.TextChanged += OnEditorTextChanged;
        }

        private void SetupSyntaxHighlighting()
        {
            try
            {
                var registryOptions = new RegistryOptions(ThemeName.DarkPlus);
                var textMateInstallation = QueryEditor.InstallTextMate(registryOptions);
                textMateInstallation.SetGrammar(
                    registryOptions.GetScopeByLanguageId(
                        registryOptions.GetLanguageByExtension(".sql").Id));
            }
            catch
            {
                // Editor still works without syntax highlighting
            }
        }

        private void OnDataContextChanged(object? sender, EventArgs e)
        {
            if (_currentViewModel != null && _propertyChangedHandler != null)
                _currentViewModel.PropertyChanged -= _propertyChangedHandler;

            if (DataContext is QueryDocumentViewModel viewModel)
            {
                _currentViewModel = viewModel;

                _isUpdatingText = true;
                QueryEditor.Document.Text = viewModel.QueryText ?? string.Empty;
                _isUpdatingText = false;

                _propertyChangedHandler = (s, args) =>
                {
                    if (args.PropertyName == nameof(QueryDocumentViewModel.QueryText) && !_isUpdatingText)
                    {
                        _isUpdatingText = true;
                        QueryEditor.Document.Text = viewModel.QueryText ?? string.Empty;
                        _isUpdatingText = false;
                    }
                };
                viewModel.PropertyChanged += _propertyChangedHandler;
            }
            else
            {
                _currentViewModel = null;
                _propertyChangedHandler = null;
            }
        }

        private void OnEditorTextChanged(object? sender, EventArgs e)
        {
            if (!_isUpdatingText && DataContext is QueryDocumentViewModel viewModel)
            {
                _isUpdatingText = true;
                viewModel.QueryText = QueryEditor.Document.Text;
                _isUpdatingText = false;
            }
        }
    }
}
