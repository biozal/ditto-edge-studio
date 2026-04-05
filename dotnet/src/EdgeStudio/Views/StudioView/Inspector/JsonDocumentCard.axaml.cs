using Avalonia.Controls;
using Avalonia.Controls.Documents;
using Avalonia.Media;
using System;

namespace EdgeStudio.Views.StudioView.Inspector
{
    public partial class JsonDocumentCard : UserControl
    {
        // DarkPlus-inspired JSON colors
        private static readonly IBrush KeyBrush = new SolidColorBrush(Color.FromRgb(156, 220, 254));   // light blue
        private static readonly IBrush StringBrush = new SolidColorBrush(Color.FromRgb(206, 145, 120)); // orange
        private static readonly IBrush NumberBrush = new SolidColorBrush(Color.FromRgb(181, 206, 168)); // green
        private static readonly IBrush BoolNullBrush = new SolidColorBrush(Color.FromRgb(86, 156, 214)); // blue
        private static readonly IBrush PunctuationBrush = new SolidColorBrush(Color.FromRgb(180, 180, 180)); // grey

        public JsonDocumentCard()
        {
            InitializeComponent();
            DataContextChanged += OnDataContextChanged;
        }

        private void OnDataContextChanged(object? sender, EventArgs e)
        {
            JsonBlock.Inlines?.Clear();
            if (DataContext is not string json || string.IsNullOrEmpty(json))
                return;

            Colorize(json, JsonBlock.Inlines!);
        }

        private static void Colorize(string json, InlineCollection inlines)
        {
            int i = 0;
            int len = json.Length;

            while (i < len)
            {
                char c = json[i];

                // Whitespace
                if (char.IsWhiteSpace(c))
                {
                    int start = i;
                    while (i < len && char.IsWhiteSpace(json[i])) i++;
                    inlines.Add(new Run(json[start..i]));
                    continue;
                }

                // String (key or value)
                if (c == '"')
                {
                    int start = i;
                    i++; // skip opening quote
                    while (i < len && json[i] != '"')
                    {
                        if (json[i] == '\\') i++; // skip escaped char
                        i++;
                    }
                    if (i < len) i++; // skip closing quote
                    var text = json[start..i];

                    // Look ahead to see if this is a key (followed by ':')
                    int peek = i;
                    while (peek < len && char.IsWhiteSpace(json[peek])) peek++;
                    bool isKey = peek < len && json[peek] == ':';

                    inlines.Add(new Run(text) { Foreground = isKey ? KeyBrush : StringBrush });
                    continue;
                }

                // Numbers
                if (c == '-' || (c >= '0' && c <= '9'))
                {
                    int start = i;
                    if (c == '-') i++;
                    while (i < len && ((json[i] >= '0' && json[i] <= '9') || json[i] == '.' || json[i] == 'e' || json[i] == 'E' || json[i] == '+' || json[i] == '-'))
                        i++;
                    inlines.Add(new Run(json[start..i]) { Foreground = NumberBrush });
                    continue;
                }

                // true / false / null
                if (c == 't' && i + 4 <= len && json.AsSpan(i, 4).SequenceEqual("true"))
                {
                    inlines.Add(new Run("true") { Foreground = BoolNullBrush });
                    i += 4;
                    continue;
                }
                if (c == 'f' && i + 5 <= len && json.AsSpan(i, 5).SequenceEqual("false"))
                {
                    inlines.Add(new Run("false") { Foreground = BoolNullBrush });
                    i += 5;
                    continue;
                }
                if (c == 'n' && i + 4 <= len && json.AsSpan(i, 4).SequenceEqual("null"))
                {
                    inlines.Add(new Run("null") { Foreground = BoolNullBrush });
                    i += 4;
                    continue;
                }

                // Punctuation: { } [ ] , :
                inlines.Add(new Run(c.ToString()) { Foreground = PunctuationBrush });
                i++;
            }
        }
    }
}
