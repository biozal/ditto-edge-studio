using Avalonia.Controls;
using AvaloniaEdit.TextMate;
using System;
using TextMateSharp.Grammars;

namespace EdgeStudio.Views.StudioView.Inspector
{
    public partial class JsonDocumentCard : UserControl
    {
        // Shared across all card instances — constructed once per app lifetime
        private static readonly RegistryOptions RegistryOptions =
            new(ThemeName.DarkPlus);

        // Must be stored as a field — if GC'd, syntax highlighting stops working
        private TextMate.Installation? _textMateInstallation;

        public JsonDocumentCard()
        {
            InitializeComponent();
            SetupSyntaxHighlighting();
            DataContextChanged += OnDataContextChanged;
        }

        private void SetupSyntaxHighlighting()
        {
            try
            {
                _textMateInstallation = JsonEditor.InstallTextMate(RegistryOptions);
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
            JsonEditor.Document.Text = DataContext is string json ? json : string.Empty;
        }
    }
}
