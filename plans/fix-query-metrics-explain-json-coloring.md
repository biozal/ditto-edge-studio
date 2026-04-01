# Plan: Color-Format EXPLAIN Output JSON in Query Metrics Detail View

## Problem
The EXPLAIN Output section in `QueryMetricsDetailView.axaml` displays raw JSON in a plain `TextBox` with no syntax highlighting. The inspector's `JsonDocumentCard` already has color-formatted JSON using AvaloniaEdit + TextMate. We need to bring the same treatment to the detail view.

## Root Cause
`QueryMetricsDetailView.axaml` (lines 169-177) uses a basic `TextBox` for the EXPLAIN output, while `JsonDocumentCard` uses `AvaloniaEdit.TextEditor` with TextMate syntax highlighting (DarkPlus theme + JSON grammar).

## Solution
Replace the plain `TextBox` in the EXPLAIN Output section with an AvaloniaEdit `TextEditor` that has TextMate JSON syntax highlighting, matching the approach already used in `JsonDocumentCard.axaml.cs`.

## Files to Change

### 1. `Views/StudioView/Details/QueryMetricsDetailView.axaml`
**What:** Replace the EXPLAIN Output `TextBox` with an AvaloniaEdit `TextEditor`.

Replace this (lines ~169-177):
```xml
<Border Background="{DynamicResource SukiBackground}"
        CornerRadius="6"
        Padding="8">
    <TextBox Text="{Binding ExplainOutput}"
             IsReadOnly="True"
             FontFamily="Cascadia Code, Consolas, monospace"
             FontSize="12"
             TextWrapping="Wrap"
             AcceptsReturn="True"
             Background="Transparent"
             BorderThickness="0"/>
</Border>
```

With:
```xml
<Border Background="{DynamicResource SukiBackground}"
        CornerRadius="6"
        Padding="8">
    <avaloniaEdit:TextEditor x:Name="ExplainEditor"
                             IsReadOnly="True"
                             FontFamily="Cascadia Code, Consolas, monospace"
                             FontSize="14"
                             ShowLineNumbers="False"
                             WordWrap="True"
                             HorizontalScrollBarVisibility="Auto"
                             VerticalScrollBarVisibility="Auto"
                             Background="Transparent"
                             Foreground="{DynamicResource DittoCardText}"/>
</Border>
```

Also add the AvaloniaEdit namespace to the AXAML header:
```xml
xmlns:avaloniaEdit="https://github.com/avaloniaui/avaloniaedit"
```

### 2. `Views/StudioView/Details/QueryMetricsDetailView.axaml.cs`
**What:** Add code-behind to set up TextMate syntax highlighting and bind the ExplainOutput text.

Add:
- A `TextMate.Installation` field (same pattern as `JsonDocumentCard.axaml.cs`)
- In constructor (after `InitializeComponent`), call `SetupSyntaxHighlighting()`
- Subscribe to `DataContextChanged` to update the editor text from `ExplainOutput`
- `SetupSyntaxHighlighting()` method: install TextMate with `DarkPlus` theme + JSON grammar (copy from `JsonDocumentCard.axaml.cs` lines 24-38)
- Update text method: read `ExplainOutput` from the ViewModel and set `ExplainEditor.Document.Text`

Reference implementation in `JsonDocumentCard.axaml.cs`:
```csharp
private static readonly RegistryOptions RegistryOptions = new(ThemeName.DarkPlus);
private TextMate.Installation? _textMateInstallation;

private void SetupSyntaxHighlighting()
{
    try
    {
        _textMateInstallation = ExplainEditor.InstallTextMate(RegistryOptions);
        _textMateInstallation.SetGrammar(
            RegistryOptions.GetScopeByLanguageId(
                RegistryOptions.GetLanguageByExtension(".json").Id));
    }
    catch { /* Falls back to plain text */ }
}
```

For binding the text, subscribe to `DataContextChanged` and read the ViewModel's `ExplainOutput` property:
```csharp
private void OnDataContextChanged(object? sender, EventArgs e)
{
    if (DataContext is QueryMetricsViewModel vm)
        ExplainEditor.Document.Text = vm.ExplainOutput ?? string.Empty;
}
```

**Note:** Since `TextEditor` doesn't support direct `Text="{Binding}"`, we must set `Document.Text` in code-behind — this is the same pattern `JsonDocumentCard` uses.

## Files NOT Changed
- `QueryMetricsViewModel.cs` — no changes needed, `ExplainOutput` property stays as-is
- `JsonDocumentCard.axaml.cs` — reference only, not modified
- `ExplainResultsView.axaml` — separate inspector view, out of scope

## Verification
1. `dotnet build EdgeStudio/EdgeStudio.csproj` — must compile clean
2. Open Query Metrics detail for a query that has EXPLAIN output
3. Confirm JSON keys, strings, numbers, booleans render in different colors matching the inspector's JSON card styling
