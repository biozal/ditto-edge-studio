using Avalonia.Controls;
using AvaloniaEdit.Editing;
using AvaloniaEdit.TextMate;
using EdgeStudio.ViewModels;
using System;
using System.ComponentModel;
using TextMateSharp.Grammars;

namespace EdgeStudio.Views.Workspaces
{
    public partial class QueryDocumentView : UserControl
    {
        private bool _isUpdatingText;
        private QueryDocumentViewModel? _currentViewModel;
        private PropertyChangedEventHandler? _propertyChangedHandler;

        public QueryDocumentView()
        {
            InitializeComponent();

            // Set up SQL syntax highlighting
            SetupSyntaxHighlighting();

            // Wire up TextEditor to ViewModel
            DataContextChanged += OnDataContextChanged;
            QueryEditor.TextChanged += OnEditorTextChanged;
        }

        private void SetupSyntaxHighlighting()
        {
            try
            {
                // Create TextMate installation
                var registryOptions = new RegistryOptions(ThemeName.DarkPlus);
                var textMateInstallation = QueryEditor.InstallTextMate(registryOptions);

                // Set SQL grammar
                textMateInstallation.SetGrammar(registryOptions.GetScopeByLanguageId(registryOptions.GetLanguageByExtension(".sql").Id));
            }
            catch
            {
                // If syntax highlighting fails, editor will still work without it
            }
        }

        private void OnDataContextChanged(object? sender, EventArgs e)
        {
            // Unsubscribe from old ViewModel
            if (_currentViewModel != null && _propertyChangedHandler != null)
            {
                _currentViewModel.PropertyChanged -= _propertyChangedHandler;
            }

            if (DataContext is QueryDocumentViewModel viewModel)
            {
                _currentViewModel = viewModel;

                // Always update editor text when switching tabs, even if empty
                _isUpdatingText = true;
                QueryEditor.Document.Text = viewModel.QueryText ?? string.Empty;
                _isUpdatingText = false;

                // Subscribe to ViewModel property changes
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
