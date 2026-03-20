using Avalonia.Controls;
using AvaloniaEdit.TextMate;
using EdgeStudio.ViewModels;
using System;
using System.ComponentModel;
using TextMateSharp.Grammars;

namespace EdgeStudio.Views.StudioView.Inspector
{
    public partial class DocumentViewerView : UserControl
    {
        // Shared with JsonDocumentCard — only one RegistryOptions built per app lifetime
        private static readonly RegistryOptions RegistryOptions =
            new(ThemeName.DarkPlus);

        // Must be stored as a field — if GC'd, syntax highlighting stops working
        private TextMate.Installation? _textMateInstallation;
        private QueryDocumentViewModel? _currentViewModel;
        private PropertyChangedEventHandler? _propertyChangedHandler;

        public DocumentViewerView()
        {
            InitializeComponent();
            SetupSyntaxHighlighting();
            DataContextChanged += OnDataContextChanged;
        }

        private void SetupSyntaxHighlighting()
        {
            try
            {
                _textMateInstallation = JsonViewer.InstallTextMate(RegistryOptions);
                _textMateInstallation.SetGrammar(
                    RegistryOptions.GetScopeByLanguageId(
                        RegistryOptions.GetLanguageByExtension(".json").Id));
            }
            catch
            {
                // Editor still works as plain text without syntax highlighting
            }
        }

        private void OnDataContextChanged(object? sender, EventArgs e)
        {
            // Unsubscribe from old viewmodel
            if (_currentViewModel != null && _propertyChangedHandler != null)
                _currentViewModel.PropertyChanged -= _propertyChangedHandler;

            _currentViewModel = DataContext as QueryDocumentViewModel;

            if (_currentViewModel != null)
            {
                // Set initial content
                UpdateEditorText(_currentViewModel.SelectedDocumentJson);

                // Subscribe to future changes
                _propertyChangedHandler = (s, args) =>
                {
                    if (args.PropertyName == nameof(QueryDocumentViewModel.SelectedDocumentJson))
                        UpdateEditorText(_currentViewModel.SelectedDocumentJson);
                };
                _currentViewModel.PropertyChanged += _propertyChangedHandler;
            }
            else
            {
                UpdateEditorText(null);
                _propertyChangedHandler = null;
            }
        }

        private void UpdateEditorText(string? json)
        {
            JsonViewer.Document.Text = string.IsNullOrEmpty(json) ? string.Empty : json;
        }
    }
}
