using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Documents;
using Avalonia.Layout;
using Avalonia.Media;

namespace EdgeStudio.Views.Inspector;

internal static class SimpleMarkdownRenderer
{
    public static Control Render(string markdown)
    {
        var panel = new StackPanel { Spacing = 0 };
        var lines = markdown.Replace("\r\n", "\n").Split('\n');
        int i = 0;

        while (i < lines.Length)
        {
            var line = lines[i].TrimEnd();

            if (string.IsNullOrWhiteSpace(line))
            {
                panel.Children.Add(new Border { Height = 6 });
                i++;
                continue;
            }

            if (line.StartsWith("#### "))
                panel.Children.Add(MakeHeading(line[5..], 13, FontWeight.Bold, 6));
            else if (line.StartsWith("### "))
                panel.Children.Add(MakeHeading(line[4..], 13, FontWeight.Bold, 8));
            else if (line.StartsWith("## "))
                panel.Children.Add(MakeHeading(line[3..], 15, FontWeight.Bold, 10));
            else if (line.StartsWith("# "))
                panel.Children.Add(MakeHeading(line[2..], 18, FontWeight.Bold, 12));
            else if (line == "---" || line == "***" || line == "___")
                panel.Children.Add(MakeHR());
            else if (line.StartsWith("```"))
            {
                var codeLines = new List<string>();
                i++;
                while (i < lines.Length && !lines[i].TrimEnd().StartsWith("```"))
                    codeLines.Add(lines[i++]);
                panel.Children.Add(MakeCodeBlock(string.Join("\n", codeLines)));
            }
            else if (line.StartsWith("> "))
                panel.Children.Add(MakeBlockquote(line[2..]));
            else if (line.StartsWith("| ") || line.StartsWith("|"))
            {
                var tableLines = new List<string>();
                while (i < lines.Length && (lines[i].TrimEnd().StartsWith("| ") || lines[i].TrimEnd().StartsWith("|")))
                    tableLines.Add(lines[i++].TrimEnd());
                panel.Children.Add(MakeTable(tableLines));
                continue;
            }
            else if (line.StartsWith("- ") || line.StartsWith("* "))
                panel.Children.Add(MakeListItem("•  " + line[2..], numbered: false));
            else if (Regex.IsMatch(line, @"^\d+\.\s+"))
            {
                var m = Regex.Match(line, @"^(\d+)\.\s+(.*)");
                panel.Children.Add(MakeListItem(m.Groups[1].Value + ".  " + m.Groups[2].Value, numbered: true));
            }
            else
                panel.Children.Add(MakeParagraph(line));

            i++;
        }

        return panel;
    }

    private static Border MakeHeading(string text, double fontSize, FontWeight weight, double topMargin) =>
        new()
        {
            Margin = new Thickness(0, topMargin, 0, 3),
            Child = new TextBlock
            {
                Text = StripInlineMarkers(text),
                FontSize = fontSize,
                FontWeight = weight,
                TextWrapping = TextWrapping.Wrap,
            }
        };

    private static Border MakeHR() =>
        new()
        {
            Height = 1,
            Margin = new Thickness(0, 6, 0, 6),
            Opacity = 0.25,
            Background = Brushes.Gray
        };

    private static Border MakeCodeBlock(string code) =>
        new()
        {
            Margin = new Thickness(0, 4, 0, 4),
            Padding = new Thickness(10, 8, 10, 8),
            CornerRadius = new CornerRadius(4),
            Background = new SolidColorBrush(Color.FromArgb(180, 20, 20, 30)),
            Child = new SelectableTextBlock
            {
                Text = code,
                FontFamily = new FontFamily("Cascadia Code,Consolas,Courier New,monospace"),
                FontSize = 11,
                Foreground = new SolidColorBrush(Color.FromRgb(200, 210, 220)),
                TextWrapping = TextWrapping.Wrap
            }
        };

    private static Border MakeBlockquote(string text) =>
        new()
        {
            Margin = new Thickness(0, 3, 0, 3),
            Padding = new Thickness(10, 5, 10, 5),
            BorderBrush = new SolidColorBrush(Color.FromRgb(80, 140, 220)),
            BorderThickness = new Thickness(3, 0, 0, 0),
            Background = new SolidColorBrush(Color.FromArgb(30, 80, 140, 220)),
            Child = MakeInlineTextBlock(text, 11)
        };

    private static Border MakeListItem(string text, bool numbered) =>
        new()
        {
            Margin = new Thickness(12, 1, 0, 1),
            Child = MakeInlineTextBlock(text, 12)
        };

    private static Control MakeParagraph(string text) =>
        new Border
        {
            Margin = new Thickness(0, 1, 0, 1),
            Child = MakeInlineTextBlock(text, 12)
        };

    private static SelectableTextBlock MakeInlineTextBlock(string text, double fontSize)
    {
        var tb = new SelectableTextBlock
        {
            FontSize = fontSize,
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.9
        };

        foreach (var inline in ParseInlines(text))
            tb.Inlines!.Add(inline);

        return tb;
    }

    private static IEnumerable<Inline> ParseInlines(string text)
    {
        var pattern = @"\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`|\[(.+?)\]\((.+?)\)";
        int last = 0;

        foreach (Match m in Regex.Matches(text, pattern))
        {
            if (m.Index > last)
                yield return new Run(text[last..m.Index]);

            if (m.Groups[1].Success)
                yield return new Run(m.Groups[1].Value) { FontWeight = FontWeight.Bold };
            else if (m.Groups[2].Success)
                yield return new Run(m.Groups[2].Value) { FontStyle = FontStyle.Italic };
            else if (m.Groups[3].Success)
                yield return new Run(m.Groups[3].Value)
                {
                    FontFamily = new FontFamily("Cascadia Code,Consolas,Courier New,monospace"),
                    FontSize = 10,
                    Background = new SolidColorBrush(Color.FromArgb(100, 80, 80, 100))
                };
            else if (m.Groups[4].Success)
                yield return new Run(m.Groups[4].Value) { TextDecorations = TextDecorations.Underline };

            last = m.Index + m.Length;
        }

        if (last < text.Length)
            yield return new Run(text[last..]);

        if (last == 0)
            yield return new Run(text);
    }

    private static Control MakeTable(List<string> lines)
    {
        var rows = lines
            .Where(l => !Regex.IsMatch(l.Trim(), @"^\|[-| :]+\|$"))
            .Select(l => l.Trim('|').Split('|').Select(c => c.Trim()).ToList())
            .ToList();

        if (rows.Count == 0) return new Border();

        int cols = rows.Max(r => r.Count);
        var grid = new Grid { Margin = new Thickness(0, 4, 0, 8) };

        for (int c = 0; c < cols; c++)
            grid.ColumnDefinitions.Add(new ColumnDefinition(GridLength.Star));
        for (int r = 0; r < rows.Count; r++)
            grid.RowDefinitions.Add(new RowDefinition(GridLength.Auto));

        for (int r = 0; r < rows.Count; r++)
        {
            bool isHeader = r == 0;
            for (int c = 0; c < rows[r].Count && c < cols; c++)
            {
                var cell = new Border
                {
                    Padding = new Thickness(6, 3, 6, 3),
                    BorderBrush = new SolidColorBrush(Color.FromArgb(50, 180, 180, 180)),
                    BorderThickness = new Thickness(0, 0, 0, 1),
                    Background = isHeader
                        ? new SolidColorBrush(Color.FromArgb(30, 100, 100, 140))
                        : Brushes.Transparent,
                    Child = MakeInlineTextBlock(rows[r][c], isHeader ? 11 : 11)
                };
                if (isHeader)
                    ((SelectableTextBlock)cell.Child!).FontWeight = FontWeight.SemiBold;
                Grid.SetRow(cell, r);
                Grid.SetColumn(cell, c);
                grid.Children.Add(cell);
            }
        }

        return grid;
    }

    private static string StripInlineMarkers(string text) =>
        Regex.Replace(text, @"\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`", m =>
            m.Groups[1].Success ? m.Groups[1].Value :
            m.Groups[2].Success ? m.Groups[2].Value :
            m.Groups[3].Value);
}
