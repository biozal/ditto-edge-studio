# Plan: JSON Results Syntax Highlighting & Layout Fixes

## Goal

Replace the plain read-only `TextBox` in each JSON result card with a full
`AvaloniaEdit.TextEditor` configured in read-only mode with JSON syntax
highlighting via TextMateSharp. Also fix vertical alignment so results are
always top-anchored, and increase the font size.

---

## Current State

`JsonResultsView.axaml` renders one card per document using an `ItemsControl`.
Each card contains a plain `TextBox`:

```xml
<TextBox Text="{Binding}"
         IsReadOnly="True"
         FontFamily="Cascadia Code, Consolas, monospace"
         FontSize="13"
         AcceptsReturn="True"
         TextWrapping="NoWrap"
         Background="Transparent"
         BorderThickness="0"
         IsHitTestVisible="False"/>
```

Problems:
- No JSON syntax highlighting — all text is the same flat colour
- Font size is 13pt (hard to read in the panel)
- `ItemsControl` defaults to `VerticalAlignment="Stretch"`, which can make a
  small result set appear vertically centered in the scroll area rather than
  pinned to the top

---

## Chosen Approach: `JsonDocumentCard` UserControl

`AvaloniaEdit.TextEditor` does **not** expose a standard XAML-bindable `Text`
property. Content must be set via `editor.Document.Text` in code-behind.
Because the result list uses a `DataTemplate`, the cleanest solution is a
small wrapper `UserControl` that owns the `TextEditor` and reacts to
`DataContextChanged` to push the JSON string into the editor.

`QueryEditorView` already establishes the exact pattern for SQL highlighting —
we mirror it for JSON.

### Performance note

`RegistryOptions` (TextMateSharp grammar definitions) is expensive to
construct. It is declared `static` and shared across all card instances so it
is only built once per app lifetime.

---

## Files to Create

### 1. `EdgeStudio/Views/StudioView/Inspector/JsonDocumentCard.axaml` *(new)*

Minimal XAML — just the `TextEditor`. Layout/sizing is handled by disabling
the editor's internal scrollbars so the parent `ScrollViewer` (in
`JsonResultsView`) is the only scrolling container.

```xml
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:avaloniaEdit="https://github.com/avaloniaui/avaloniaedit"
             x:Class="EdgeStudio.Views.StudioView.Inspector.JsonDocumentCard">

    <avaloniaEdit:TextEditor x:Name="JsonEditor"
                             IsReadOnly="True"
                             FontFamily="Cascadia Code, Consolas, monospace"
                             FontSize="14"
                             ShowLineNumbers="False"
                             WordWrap="False"
                             HorizontalScrollBarVisibility="Auto"
                             VerticalScrollBarVisibility="Disabled"
                             Background="{DynamicResource SukiBackground}"
                             Foreground="{DynamicResource DittoCardText}"/>
</UserControl>
```

Key settings explained:
- `IsReadOnly="True"` — user cannot edit the content
- `VerticalScrollBarVisibility="Disabled"` — makes the editor report its full
  content height to the layout system instead of collapsing to a fixed size;
  the outer `ScrollViewer` in `JsonResultsView` handles vertical scrolling
- `HorizontalScrollBarVisibility="Auto"` — wide JSON lines can still be
  scrolled horizontally within each card
- `ShowLineNumbers="False"` — unnecessary in a read-only result list
- `FontSize="14"` — up from 13

### 2. `EdgeStudio/Views/StudioView/Inspector/JsonDocumentCard.axaml.cs` *(new)*

```csharp
using Avalonia.Controls;
using AvaloniaEdit.TextMate;
using System;
using TextMateSharp.Grammars;

namespace EdgeStudio.Views.StudioView.Inspector
{
    public partial class JsonDocumentCard : UserControl
    {
        // Shared across all card instances — built once, never rebuilt
        private static readonly RegistryOptions RegistryOptions =
            new(ThemeName.DarkPlus);

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
                var installation = JsonEditor.InstallTextMate(RegistryOptions);
                installation.SetGrammar(
                    RegistryOptions.GetScopeByLanguageId(
                        RegistryOptions.GetLanguageByExtension(".json").Id));
            }
            catch
            {
                // Editor still works without syntax highlighting
            }
        }

        private void OnDataContextChanged(object? sender, EventArgs e)
        {
            if (DataContext is string json)
                JsonEditor.Document.Text = json;
            else
                JsonEditor.Document.Text = string.Empty;
        }
    }
}
```

---

## Files to Modify

### 3. `JsonResultsView.axaml`

Two changes:
1. Replace `TextBox` with `<local:JsonDocumentCard/>`
2. Add `VerticalAlignment="Top"` to the `ItemsControl` so results pin to the
   top when the result set is smaller than the panel

```xml
<UserControl ...
             xmlns:local="using:EdgeStudio.Views.StudioView.Inspector"
             x:DataType="vm:JsonResultsViewModel">

    <ScrollViewer HorizontalScrollBarVisibility="Disabled"
                  VerticalScrollBarVisibility="Auto">
        <ItemsControl ItemsSource="{Binding PagedDocuments}"
                      Margin="4,0,4,4"
                      VerticalAlignment="Top">
            <ItemsControl.ItemTemplate>
                <DataTemplate>
                    <Button Command="{Binding $parent[ItemsControl].DataContext.SelectDocumentCommand}"
                            CommandParameter="{Binding}"
                            Padding="0" Margin="0,4,0,0"
                            Background="Transparent" BorderThickness="0"
                            HorizontalAlignment="Stretch"
                            HorizontalContentAlignment="Stretch">
                        <Border Background="{DynamicResource SukiBackground}"
                                CornerRadius="6"
                                Padding="4"
                                Cursor="Hand">
                            <!-- IsHitTestVisible="False" lets the Button catch the click -->
                            <local:JsonDocumentCard DataContext="{Binding}"
                                                    IsHitTestVisible="False"/>
                        </Border>
                    </Button>
                </DataTemplate>
            </ItemsControl.ItemTemplate>
        </ItemsControl>
    </ScrollViewer>
</UserControl>
```

Note: `Padding` on the `Border` drops from `10,10` to `4` because
`AvaloniaEdit` has its own internal padding. Net visual result is similar.

---

## Design Decisions & Tradeoffs

### Why not a single editor showing all results concatenated?
A single `TextEditor` showing all paged documents as one JSON array would be
simpler, but:
- The `SelectDocumentCommand` (which populates the Document Viewer in the
  right inspector panel) requires knowing *which* individual document was
  clicked — that's lost in a single merged view
- Card-per-document makes the visual separation between documents explicit

### Why `ThemeName.DarkPlus`?
The existing `QueryEditorView` uses `DarkPlus`. The app currently targets dark
mode by default. `DarkPlus` provides excellent JSON token colours (strings
green, keys yellow, numbers blue) that work well on the dark SukiBackground.

**Limitation**: if the user switches to SukiUI light mode the editor content
area will still render with the dark colour scheme. Addressing this requires
subscribing to the `Application.ActualThemeVariantChanged` event and
reinstalling TextMate with `ThemeName.LightPlus` — intentionally left as a
future improvement.

### Why a static `RegistryOptions`?
TextMateSharp parses several MB of grammar JSON on first construction.
With up to 250 cards visible per page, creating 250 `RegistryOptions` instances
would be very slow. A single static instance is constructed once and reused by
all card instances.

---

## Verification Steps

After implementation:

1. **Build** — `dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal`
2. **Run tests** — `dotnet test EdgeStudioTests/EdgeStudioTests.csproj --no-build`
3. **Manual: Syntax highlighting** — Execute a `SELECT` query, switch to JSON
   tab, confirm JSON keys are a different colour from string values and
   numbers
4. **Manual: Top alignment** — With a 1–3 doc result set, confirm cards render
   flush to the top of the panel, not centered
5. **Manual: Font size** — Confirm text is visibly larger than before (14pt)
6. **Manual: Selection still works** — Click any JSON card, confirm the
   Document Viewer (right inspector panel) updates with that document's JSON
7. **Manual: Pagination** — With 30+ docs, navigate pages and confirm each
   page renders cards with correct syntax highlighting

---

## Out of Scope (future follow-up)

- Light-mode TextMate theme (switch to `LightPlus` when SukiUI theme is light)
- Updating `DocumentViewerView.axaml` (right-panel document viewer) to also
  use AvaloniaEdit — currently uses a plain `TextBox`; worth doing for
  consistency but not requested in this task
