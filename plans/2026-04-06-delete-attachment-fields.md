# Delete Attachment Fields — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to right-click a document in query results, select "Delete Attachment...", choose which attachment fields to remove, and execute DQL UPDATE statements to null those fields.

**Architecture:** Both platforms follow the existing "Add Attachment" event chain: context menu → callback/event → message → handler → dialog/sheet → DQL execution. The delete dialog shows checkboxes for detected attachment fields and executes `UPDATE <collection> SET <field> = null WHERE _id = '<docId>'` for each selected field.

**Tech Stack:** .NET (Avalonia/SukiUI/CommunityToolkit.Mvvm), SwiftUI (macOS/iPadOS)

---

## File Structure

### .NET — New Files
| File | Responsibility |
|------|---------------|
| `dotnet/src/EdgeStudio/Views/DeleteAttachmentWindow.axaml` | Dialog UI — checkboxes for attachment fields, Delete/Cancel |
| `dotnet/src/EdgeStudio/Views/DeleteAttachmentWindow.axaml.cs` | Dialog code-behind — populates fields, returns selections |

### .NET — Modified Files
| File | Change |
|------|--------|
| `dotnet/src/EdgeStudio.Shared/Messages/AttachmentMessages.cs` | Add `DeleteAttachmentRequestedMessage` record |
| `dotnet/src/EdgeStudio/ViewModels/JsonResultsViewModel.cs` | Add `DeleteAttachmentRequested` event + command |
| `dotnet/src/EdgeStudio/ViewModels/TableResultsViewModel.cs` | Add `DeleteAttachmentRequested` event + method |
| `dotnet/src/EdgeStudio/ViewModels/QueryDocumentViewModel.cs` | Subscribe to delete events, send message |
| `dotnet/src/EdgeStudio/ViewModels/EdgeStudioViewModel.cs` | Handle message, open dialog, execute DQL |
| `dotnet/src/EdgeStudio/Views/StudioView/Inspector/JsonResultsView.axaml` | Add "Delete Attachment..." menu item |
| `dotnet/src/EdgeStudio/Views/StudioView/Inspector/TableResultsView.axaml` | Add "Delete Attachment..." menu item |
| `dotnet/src/EdgeStudioTests/AttachmentTests.cs` | Tests for delete flow |

### SwiftUI — New Files
| File | Responsibility |
|------|---------------|
| `SwiftUI/EdgeStudio/Components/DeleteAttachmentSheet.swift` | Sheet UI — toggles for attachment fields, Delete/Cancel |

### SwiftUI — Modified Files
| File | Change |
|------|--------|
| `SwiftUI/EdgeStudio/Components/ResultJsonViewer.swift` | Add `onDeleteAttachment` callback + menu item |
| `SwiftUI/EdgeStudio/Components/ResultTableViewer.swift` | Add `onDeleteAttachment` callback + menu items |
| `SwiftUI/EdgeStudio/Components/QueryResultsView.swift` | Propagate `onDeleteAttachment` callback |
| `SwiftUI/EdgeStudio/Views/StudioView/Details/DetailViews.swift` | Wire `onDeleteAttachment` to ViewModel |
| `SwiftUI/EdgeStudio/Views/MainStudioView.swift` | Add state, sheet, requestDelete, executeDelete methods |
| `SwiftUI/EdgeStudioUnitTests/Models/AttachmentTests.swift` | Tests for delete flow |

---

## .NET Tasks

### Task 1: Add DeleteAttachmentRequestedMessage

**Files:**
- Modify: `dotnet/src/EdgeStudio.Shared/Messages/AttachmentMessages.cs`

- [ ] **Step 1: Add the message record**

Add after the `AttachmentAddedMessage` record (line 12):

```csharp
/// <summary>
/// Sent when the user requests to delete attachment field(s) from a document.
/// </summary>
public record DeleteAttachmentRequestedMessage(string DocumentJson, string Collection, string QueryMode);
```

- [ ] **Step 2: Build to verify**

```bash
cd dotnet/src && dotnet build EdgeStudio.Shared/EdgeStudio.Shared.csproj --verbosity minimal
```

- [ ] **Step 3: Commit**

```bash
git add dotnet/src/EdgeStudio.Shared/Messages/AttachmentMessages.cs
git commit -m "feat(attachments/dotnet): add DeleteAttachmentRequestedMessage"
```

---

### Task 2: Add delete events and commands to results ViewModels

**Files:**
- Modify: `dotnet/src/EdgeStudio/ViewModels/JsonResultsViewModel.cs`
- Modify: `dotnet/src/EdgeStudio/ViewModels/TableResultsViewModel.cs`

- [ ] **Step 1: Add event and command to JsonResultsViewModel**

After the `AddAttachmentRequested` event (line 38), add:

```csharp
/// <summary>Fired when the user requests to delete attachment field(s) from a document.</summary>
public event Action<string>? DeleteAttachmentRequested;
```

After the `AddAttachment` command (line 87), add:

```csharp
[RelayCommand]
private void DeleteAttachment(string json)
{
    DeleteAttachmentRequested?.Invoke(json);
}
```

- [ ] **Step 2: Add event and method to TableResultsViewModel**

After the `AddAttachmentRequested` event (line 37), add:

```csharp
public event Action<string>? DeleteAttachmentRequested;
```

After the `RequestAddAttachment` method (line 105), add:

```csharp
public void RequestDeleteAttachment(TableRow row)
{
    DeleteAttachmentRequested?.Invoke(row.OriginalJson);
}
```

- [ ] **Step 3: Build to verify**

```bash
cd dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```

- [ ] **Step 4: Commit**

```bash
git add dotnet/src/EdgeStudio/ViewModels/JsonResultsViewModel.cs dotnet/src/EdgeStudio/ViewModels/TableResultsViewModel.cs
git commit -m "feat(attachments/dotnet): add delete attachment events to results ViewModels"
```

---

### Task 3: Subscribe to delete events in QueryDocumentViewModel

**Files:**
- Modify: `dotnet/src/EdgeStudio/ViewModels/QueryDocumentViewModel.cs`

- [ ] **Step 1: Subscribe to JsonResults delete event**

After `_jsonResults.AddAttachmentRequested += json => OnAddAttachmentRequested(json);` (line 134), add:

```csharp
_jsonResults.DeleteAttachmentRequested += json => OnDeleteAttachmentRequested(json);
```

- [ ] **Step 2: Subscribe to TableResults delete event**

After `_tableResults.AddAttachmentRequested += json => OnAddAttachmentRequested(json);` (line 144), add:

```csharp
_tableResults.DeleteAttachmentRequested += json => OnDeleteAttachmentRequested(json);
```

- [ ] **Step 3: Add the handler method**

After the `OnAddAttachmentRequested` method (line 281), add:

```csharp
private void OnDeleteAttachmentRequested(string documentJson)
{
    var collection = _lastCollection ?? "unknown";
    WeakReferenceMessenger.Default.Send(
        new DeleteAttachmentRequestedMessage(documentJson, collection, SelectedQueryMode));
}
```

- [ ] **Step 4: Build to verify**

```bash
cd dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```

- [ ] **Step 5: Commit**

```bash
git add dotnet/src/EdgeStudio/ViewModels/QueryDocumentViewModel.cs
git commit -m "feat(attachments/dotnet): wire delete attachment events in QueryDocumentViewModel"
```

---

### Task 4: Add context menu items to JsonResultsView and TableResultsView

**Files:**
- Modify: `dotnet/src/EdgeStudio/Views/StudioView/Inspector/JsonResultsView.axaml`
- Modify: `dotnet/src/EdgeStudio/Views/StudioView/Inspector/TableResultsView.axaml`

- [ ] **Step 1: Add menu item to JsonResultsView**

In `JsonResultsView.axaml`, after the "Add Attachment..." MenuItem (line 33), add:

```xml
<MenuItem Header="Delete Attachment..."
          Command="{Binding $parent[ItemsControl].((vm:JsonResultsViewModel)DataContext).DeleteAttachmentCommand}"
          CommandParameter="{Binding}" />
```

- [ ] **Step 2: Add menu item to TableResultsView**

In `TableResultsView.axaml`, after the "Add Attachment..." MenuItem (line 35 area), add a matching menu item. Since TableResultsView uses `x:Name` placeholders wired in code-behind, add:

```xml
<MenuItem Header="Delete Attachment..." x:Name="DeleteAttachmentMenuItem" />
```

Then in `TableResultsView.axaml.cs`, wire it in the same place where `AddAttachmentMenuItem` is wired — add the Click handler that calls `RequestDeleteAttachment` on the ViewModel.

- [ ] **Step 3: Build to verify**

```bash
cd dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```

- [ ] **Step 4: Commit**

```bash
git add dotnet/src/EdgeStudio/Views/StudioView/Inspector/JsonResultsView.axaml dotnet/src/EdgeStudio/Views/StudioView/Inspector/TableResultsView.axaml dotnet/src/EdgeStudio/Views/StudioView/Inspector/TableResultsView.axaml.cs
git commit -m "feat(attachments/dotnet): add Delete Attachment context menu items"
```

---

### Task 5: Create DeleteAttachmentWindow dialog

**Files:**
- Create: `dotnet/src/EdgeStudio/Views/DeleteAttachmentWindow.axaml`
- Create: `dotnet/src/EdgeStudio/Views/DeleteAttachmentWindow.axaml.cs`

- [ ] **Step 1: Create the XAML file**

`DeleteAttachmentWindow.axaml`:

```xml
<suki:SukiWindow xmlns="https://github.com/avaloniaui"
                 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                 xmlns:suki="using:SukiUI.Controls"
                 x:Class="EdgeStudio.Views.DeleteAttachmentWindow"
                 Title="Delete Attachment Fields"
                 Width="420" Height="400"
                 WindowStartupLocation="CenterOwner"
                 CanResize="False"
                 BackgroundStyle="Flat">

    <StackPanel Margin="20" Spacing="12">
        <TextBlock Text="Select Fields to Delete" FontWeight="Bold" FontSize="16" />

        <Grid ColumnDefinitions="Auto,*" RowDefinitions="Auto,Auto" Margin="0,0,0,8">
            <TextBlock Grid.Row="0" Grid.Column="0" Text="Collection: " Foreground="Gray" />
            <TextBlock Grid.Row="0" Grid.Column="1" x:Name="CollectionText" />
            <TextBlock Grid.Row="1" Grid.Column="0" Text="Document ID: " Foreground="Gray" />
            <TextBlock Grid.Row="1" Grid.Column="1" x:Name="DocumentIdText" TextTrimming="CharacterEllipsis" />
        </Grid>

        <Separator />

        <TextBlock Text="Attachment Fields" FontWeight="SemiBold" Margin="0,4,0,0" />

        <ScrollViewer MaxHeight="200" VerticalScrollBarVisibility="Auto">
            <ItemsControl x:Name="AttachmentList">
                <ItemsControl.ItemTemplate>
                    <DataTemplate>
                        <CheckBox IsChecked="{Binding IsSelected}" Margin="0,4">
                            <StackPanel Spacing="2">
                                <TextBlock Text="{Binding Info.FieldName}" FontWeight="SemiBold" />
                                <TextBlock FontSize="11" Foreground="Gray">
                                    <TextBlock.Text>
                                        <MultiBinding StringFormat="{}{0} · {1} · {2}">
                                            <Binding Path="Info.FileName" />
                                            <Binding Path="Info.FormattedSize" />
                                            <Binding Path="Info.MimeType" />
                                        </MultiBinding>
                                    </TextBlock.Text>
                                </TextBlock>
                            </StackPanel>
                        </CheckBox>
                    </DataTemplate>
                </ItemsControl.ItemTemplate>
            </ItemsControl>
        </ScrollViewer>

        <DockPanel Margin="0,12,0,0">
            <Button DockPanel.Dock="Right"
                    x:Name="DeleteButton"
                    Content="Delete"
                    IsEnabled="False"
                    Padding="16,8" Margin="8,0,0,0" />
            <Button DockPanel.Dock="Right"
                    x:Name="CancelButton"
                    Content="Cancel"
                    Padding="16,8" />
            <Panel />
        </DockPanel>
    </StackPanel>
</suki:SukiWindow>
```

- [ ] **Step 2: Create the code-behind file**

`DeleteAttachmentWindow.axaml.cs`:

```csharp
using Avalonia.Controls;
using EdgeStudio.Shared.Models;
using SukiUI.Controls;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;

namespace EdgeStudio.Views;

public partial class DeleteAttachmentWindow : SukiWindow
{
    public bool Confirmed { get; private set; }
    public List<AttachmentInfo> SelectedAttachments { get; private set; } = new();

    private readonly ObservableCollection<SelectableAttachment> _items = new();

    public DeleteAttachmentWindow()
    {
        InitializeComponent();
    }

    public DeleteAttachmentWindow(string collection, string documentId, List<AttachmentInfo> attachments)
    {
        InitializeComponent();
        CollectionText.Text = collection;
        DocumentIdText.Text = documentId;

        foreach (var att in attachments)
        {
            var item = new SelectableAttachment(att);
            item.PropertyChanged += (_, _) => UpdateDeleteButton();
            _items.Add(item);
        }
        AttachmentList.ItemsSource = _items;

        CancelButton.Click += (_, _) => Close();
        DeleteButton.Click += (_, _) =>
        {
            Confirmed = true;
            SelectedAttachments = _items.Where(i => i.IsSelected).Select(i => i.Info).ToList();
            Close();
        };
    }

    private void UpdateDeleteButton()
    {
        DeleteButton.IsEnabled = _items.Any(i => i.IsSelected);
    }
}

public class SelectableAttachment : INotifyPropertyChanged
{
    public AttachmentInfo Info { get; }
    private bool _isSelected;

    public bool IsSelected
    {
        get => _isSelected;
        set { _isSelected = value; OnPropertyChanged(); }
    }

    public SelectableAttachment(AttachmentInfo info) => Info = info;

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
```

- [ ] **Step 3: Build to verify**

```bash
cd dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```

- [ ] **Step 4: Commit**

```bash
git add dotnet/src/EdgeStudio/Views/DeleteAttachmentWindow.axaml dotnet/src/EdgeStudio/Views/DeleteAttachmentWindow.axaml.cs
git commit -m "feat(attachments/dotnet): add DeleteAttachmentWindow dialog"
```

---

### Task 6: Handle DeleteAttachmentRequestedMessage in EdgeStudioViewModel

**Files:**
- Modify: `dotnet/src/EdgeStudio/ViewModels/EdgeStudioViewModel.cs`

- [ ] **Step 1: Register the message handler**

After the `AddAttachmentRequestedMessage` registration (line 165), add:

```csharp
WeakReferenceMessenger.Default.Register<DeleteAttachmentRequestedMessage>(this, OnDeleteAttachmentRequested);
```

- [ ] **Step 2: Add the handler method**

After the `OnAddAttachmentRequested` handler (line 461), add:

```csharp
private async void OnDeleteAttachmentRequested(object recipient, DeleteAttachmentRequestedMessage message)
{
    if (Avalonia.Application.Current?.ApplicationLifetime is not Avalonia.Controls.ApplicationLifetimes.IClassicDesktopStyleApplicationLifetime { MainWindow: { } mainWindow })
        return;

    string documentId;
    try
    {
        using var doc = System.Text.Json.JsonDocument.Parse(message.DocumentJson);
        documentId = doc.RootElement.GetProperty("_id").ToString();
    }
    catch
    {
        return;
    }

    var attachments = AttachmentInfo.DetectTokens(message.DocumentJson);
    if (attachments.Count == 0) return;

    var dialog = new Views.DeleteAttachmentWindow(message.Collection, documentId, attachments);
    await dialog.ShowDialog(mainWindow);

    if (!dialog.Confirmed || dialog.SelectedAttachments.Count == 0)
        return;

    var serviceProvider = App.ServiceProvider;
    if (serviceProvider == null) return;
    var queryService = serviceProvider.GetRequiredService<IQueryService>();
    var safeIdentifier = new System.Text.RegularExpressions.Regex(@"^[a-zA-Z_][a-zA-Z0-9_]*$");

    try
    {
        foreach (var att in dialog.SelectedAttachments)
        {
            if (!safeIdentifier.IsMatch(att.FieldName) || !safeIdentifier.IsMatch(message.Collection))
                throw new System.InvalidOperationException($"Invalid identifier: {att.FieldName}");

            var dql = $"UPDATE {message.Collection} SET {att.FieldName} = null WHERE _id = '{documentId}'";
            await queryService.ExecuteLocalAsync(dql);
        }

        ShowSuccess($"Deleted {dialog.SelectedAttachments.Count} attachment field(s)");
    }
    catch (System.Exception ex)
    {
        ShowError($"Failed to delete attachment field(s): {ex.Message}");
    }
}
```

- [ ] **Step 3: Build to verify**

```bash
cd dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```

- [ ] **Step 4: Commit**

```bash
git add dotnet/src/EdgeStudio/ViewModels/EdgeStudioViewModel.cs
git commit -m "feat(attachments/dotnet): handle DeleteAttachmentRequestedMessage in EdgeStudioViewModel"
```

---

### Task 7: Write .NET tests

**Files:**
- Modify: `dotnet/src/EdgeStudioTests/AttachmentTests.cs`

- [ ] **Step 1: Add tests**

Append before the final `#endregion` in AttachmentTests.cs:

```csharp
#region Delete Attachment Flow Tests

public class DeleteAttachmentFlowTests
{
    [Fact]
    public void DeleteAttachmentRequestedMessage_CreatesWithCorrectProperties()
    {
        var msg = new DeleteAttachmentRequestedMessage(
            DocumentJson: """{"_id":"doc1","photo":{"id":"a","len":1,"metadata":{}}}""",
            Collection: "tasks",
            QueryMode: "Local");

        msg.DocumentJson.Should().Contain("doc1");
        msg.Collection.Should().Be("tasks");
        msg.QueryMode.Should().Be("Local");
    }

    [Fact]
    public void JsonResultsViewModel_DeleteAttachmentCommand_FiresEvent()
    {
        var vm = new JsonResultsViewModel();
        string? receivedJson = null;
        vm.DeleteAttachmentRequested += json => receivedJson = json;

        vm.DeleteAttachmentCommand.Execute("""{"_id":"1"}""");

        receivedJson.Should().Be("""{"_id":"1"}""");
    }

    [Fact]
    public void DetectTokens_UsedForDeleteDialog_FindsAttachmentFields()
    {
        var json = """
        {
            "_id": "doc1",
            "name": "test",
            "photo": { "id": "att1", "len": 2048, "metadata": { "name": "pic.png", "mimeType": "image/png" } },
            "resume": { "id": "att2", "len": 51200, "metadata": { "name": "resume.pdf", "mimeType": "application/pdf" } }
        }
        """;

        var tokens = AttachmentInfo.DetectTokens(json);

        tokens.Should().HaveCount(2);
        tokens.Select(t => t.FieldName).Should().Contain("photo").And.Contain("resume");
    }

    [Theory]
    [InlineData("photo", true)]
    [InlineData("my_field", true)]
    [InlineData("_private", true)]
    [InlineData("drop;--", false)]
    [InlineData("field name", false)]
    [InlineData("123start", false)]
    public void SafeIdentifier_ValidatesFieldNames(string name, bool expected)
    {
        var regex = new System.Text.RegularExpressions.Regex(@"^[a-zA-Z_][a-zA-Z0-9_]*$");
        regex.IsMatch(name).Should().Be(expected);
    }
}

#endregion
```

- [ ] **Step 2: Run tests**

```bash
cd dotnet/src && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --filter "FullyQualifiedName~DeleteAttachmentFlow" --logger "console;verbosity=detailed"
```

Expected: All 4 tests pass.

- [ ] **Step 3: Commit**

```bash
git add dotnet/src/EdgeStudioTests/AttachmentTests.cs
git commit -m "test(attachments/dotnet): add delete attachment flow tests"
```

---

## SwiftUI Tasks

### Task 8: Add onDeleteAttachment callback to result viewers

**Files:**
- Modify: `SwiftUI/EdgeStudio/Components/ResultJsonViewer.swift`
- Modify: `SwiftUI/EdgeStudio/Components/ResultTableViewer.swift`
- Modify: `SwiftUI/EdgeStudio/Components/QueryResultsView.swift`

- [ ] **Step 1: Add callback to ResultJsonViewer**

After `var onAddAttachment: ((String) -> Void)?` (line 22), add:

```swift
/// Callback for deleting attachment field(s) from a document
var onDeleteAttachment: ((String) -> Void)?
```

Add to the init parameter list (after `onAddAttachment` parameter around line 57):

```swift
onDeleteAttachment: ((String) -> Void)? = nil
```

And in the init body:

```swift
self.onDeleteAttachment = onDeleteAttachment
```

In the context menu (after line 224, after the "Add Attachment..." button), add:

```swift
let attachments = AttachmentInfo.detectTokens(in: jsonString)
Button {
    onDeleteAttachment?(jsonString)
} label: {
    Label("Delete Attachment...", systemImage: "trash")
}
.disabled(attachments.isEmpty)
```

- [ ] **Step 2: Add callback to ResultTableViewer**

After `var onAddAttachment: ((String) -> Void)?` (line 17), add:

```swift
var onDeleteAttachment: ((String) -> Void)?
```

In both macOS context menu (line 134 area) and iPadOS context menu (line 227 area), after the "Add Attachment..." button, add:

```swift
let attachments = AttachmentInfo.detectTokens(in: row.originalJson)
Button {
    onDeleteAttachment?(row.originalJson)
} label: {
    Label("Delete Attachment...", systemImage: "trash")
}
.disabled(attachments.isEmpty)
```

- [ ] **Step 3: Propagate through QueryResultsView**

In `QueryResultsView.swift`, after `var onAddAttachment: ((String) -> Void)?` (line 19), add:

```swift
var onDeleteAttachment: ((String) -> Void)?
```

Add to the init parameter list (after `onAddAttachment` parameter around line 53):

```swift
onDeleteAttachment: ((String) -> Void)? = nil
```

And in the init body:

```swift
self.onDeleteAttachment = onDeleteAttachment
```

Pass to `ResultJsonViewer` (after `onAddAttachment: onAddAttachment` around line 100):

```swift
onDeleteAttachment: onDeleteAttachment
```

Pass to `ResultTableViewer` (after `onAddAttachment: onAddAttachment` around line 108):

```swift
onDeleteAttachment: onDeleteAttachment
```

- [ ] **Step 4: Build in Xcode to verify**

```bash
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug -destination "platform=macOS,arch=arm64" build
```

- [ ] **Step 5: Commit**

```bash
git add SwiftUI/EdgeStudio/Components/ResultJsonViewer.swift SwiftUI/EdgeStudio/Components/ResultTableViewer.swift SwiftUI/EdgeStudio/Components/QueryResultsView.swift
git commit -m "feat(attachments/swiftui): add onDeleteAttachment callback to result viewers"
```

---

### Task 9: Create DeleteAttachmentSheet

**Files:**
- Create: `SwiftUI/EdgeStudio/Components/DeleteAttachmentSheet.swift`

- [ ] **Step 1: Create the sheet file**

Use the Xcode MCP server to create the file in the correct target:

```swift
import SwiftUI

struct DeleteAttachmentSheet: View {
    let documentId: String
    let collection: String
    let attachments: [AttachmentInfo]
    let onConfirm: ([AttachmentInfo]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selections: [String: Bool] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete Attachment Fields")
                .font(.headline)

            Group {
                LabeledContent("Collection", value: collection)
                LabeledContent("Document ID", value: documentId)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            Text("Select fields to delete:")
                .font(.subheadline)
                .fontWeight(.semibold)

            List {
                ForEach(attachments) { attachment in
                    Toggle(isOn: binding(for: attachment.fieldName)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attachment.fieldName)
                                .fontWeight(.semibold)
                            Text([attachment.fileName, attachment.formattedSize, attachment.mimeType]
                                .compactMap { $0 }
                                .joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.plain)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Button("Delete", role: .destructive) {
                    let selected = attachments.filter { selections[$0.fieldName] == true }
                    onConfirm(selected)
                    dismiss()
                }
                .disabled(!selections.values.contains(true))
            }
        }
        .padding()
        .frame(minWidth: 380, minHeight: 300)
        .onAppear {
            for att in attachments {
                selections[att.fieldName] = false
            }
        }
    }

    private func binding(for fieldName: String) -> Binding<Bool> {
        Binding(
            get: { selections[fieldName] ?? false },
            set: { selections[fieldName] = $0 }
        )
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug -destination "platform=macOS,arch=arm64" build
```

- [ ] **Step 3: Commit**

```bash
git add SwiftUI/EdgeStudio/Components/DeleteAttachmentSheet.swift
git commit -m "feat(attachments/swiftui): add DeleteAttachmentSheet"
```

---

### Task 10: Wire delete flow in DetailViews and MainStudioView

**Files:**
- Modify: `SwiftUI/EdgeStudio/Views/StudioView/Details/DetailViews.swift`
- Modify: `SwiftUI/EdgeStudio/Views/MainStudioView.swift`

- [ ] **Step 1: Wire callback in DetailViews**

In `DetailViews.swift`, in the `QueryResultsView` initializer (around line 235-246), after `onAddAttachment:`, add:

```swift
onDeleteAttachment: { json in
    viewModel.requestDeleteAttachment(documentJson: json)
}
```

- [ ] **Step 2: Add state and request method to MainStudioView ViewModel**

In `MainStudioView.swift` ViewModel, near the existing attachment state properties (around line 500 area where `showAttachmentPicker` is declared), add:

```swift
@Published var showDeleteAttachmentPicker = false
var deleteAttachmentTargetJson: String?
var deleteAttachmentTargetCollection: String?
```

After the `requestAddAttachment` method (line 1114), add:

```swift
func requestDeleteAttachment(documentJson: String) {
    deleteAttachmentTargetJson = documentJson
    deleteAttachmentTargetCollection = parseCollectionName(from: selectedQuery)
    showDeleteAttachmentPicker = true
}
```

- [ ] **Step 3: Add executeDeleteAttachment method**

After the `requestDeleteAttachment` method, add:

```swift
func executeDeleteAttachment(
    selectedAttachments: [AttachmentInfo],
    appState: AppState
) async {
    guard let json = deleteAttachmentTargetJson,
          let docId = parseDocumentId(from: json) else
    {
        appState.setError(AttachmentError.noDocumentId)
        return
    }
    guard let collection = deleteAttachmentTargetCollection else {
        appState.setError(AttachmentError.collectionNotFound)
        return
    }

    let docIdString: String = if let str = docId as? String {
        str
    } else {
        "\(docId)"
    }

    let identifierPattern = /^[a-zA-Z_][a-zA-Z0-9_]*$/

    do {
        for att in selectedAttachments {
            guard att.fieldName.wholeMatch(of: identifierPattern) != nil,
                  collection.wholeMatch(of: identifierPattern) != nil else
            {
                throw AttachmentError.invalidFieldName
            }
            let query = "UPDATE \(collection) SET \(att.fieldName) = null WHERE _id = '\(docIdString)'"
            _ = try await QueryService.shared.executeSelectedAppQuery(query: query)
        }
        Log.info("Deleted \(selectedAttachments.count) attachment field(s) from document \(docIdString)")
    } catch {
        appState.setError(error)
    }
}
```

- [ ] **Step 4: Add sheet modifier**

In `MainStudioView.swift`, after the existing `.sheet(isPresented: $viewModel.showAttachmentPicker)` modifier (around line 268), add:

```swift
.sheet(isPresented: $viewModel.showDeleteAttachmentPicker) {
    if let json = viewModel.deleteAttachmentTargetJson,
       let docId = viewModel.parseDocumentId(from: json)
    {
        let attachments = AttachmentInfo.detectTokens(in: json)
        DeleteAttachmentSheet(
            documentId: String(describing: docId),
            collection: viewModel.deleteAttachmentTargetCollection ?? "unknown",
            attachments: attachments
        ) { selected in
            Task {
                await viewModel.executeDeleteAttachment(
                    selectedAttachments: selected,
                    appState: appState
                )
            }
        }
    }
}
```

- [ ] **Step 5: Build for both platforms**

```bash
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug -destination "platform=macOS,arch=arm64" build

xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M5)" build
```

- [ ] **Step 6: Commit**

```bash
git add SwiftUI/EdgeStudio/Views/StudioView/Details/DetailViews.swift SwiftUI/EdgeStudio/Views/MainStudioView.swift
git commit -m "feat(attachments/swiftui): wire delete attachment flow end-to-end"
```

---

### Task 11: Add AttachmentError case for invalidFieldName (SwiftUI)

**Files:**
- Modify: The file containing `AttachmentError` enum

- [ ] **Step 1: Find and update AttachmentError**

Search for `AttachmentError` enum definition. If it doesn't already have `invalidFieldName`, add:

```swift
case invalidFieldName
```

With a localized description:

```swift
case .invalidFieldName:
    return "Invalid field name — must be a valid identifier"
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug -destination "platform=macOS,arch=arm64" build
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat(attachments/swiftui): add invalidFieldName error case"
```

---

### Task 12: Write SwiftUI tests

**Files:**
- Modify: `SwiftUI/EdgeStudioUnitTests/Models/AttachmentTests.swift`

- [ ] **Step 1: Add tests**

```swift
// MARK: - Delete Attachment Flow Tests

@Test("DetectTokens finds attachment fields for delete dialog")
func detectTokensForDeleteDialog() {
    let json = """
    {
        "_id": "doc1",
        "name": "test",
        "photo": { "id": "att1", "len": 2048, "metadata": { "name": "pic.png", "mimeType": "image/png" } },
        "resume": { "id": "att2", "len": 51200, "metadata": { "name": "resume.pdf", "mimeType": "application/pdf" } }
    }
    """

    let tokens = AttachmentInfo.detectTokens(in: json)

    #expect(tokens.count == 2)
    let fieldNames = tokens.map(\.fieldName)
    #expect(fieldNames.contains("photo"))
    #expect(fieldNames.contains("resume"))
}

@Test("DetectTokens returns empty for document with no attachments")
func detectTokensNoAttachments() {
    let json = """{"_id": "doc1", "name": "test", "age": 30}"""

    let tokens = AttachmentInfo.detectTokens(in: json)

    #expect(tokens.isEmpty)
}

@Test("Field name validation rejects unsafe identifiers")
func fieldNameValidation() {
    let pattern = /^[a-zA-Z_][a-zA-Z0-9_]*$/
    #expect("photo".wholeMatch(of: pattern) != nil)
    #expect("my_field".wholeMatch(of: pattern) != nil)
    #expect("drop;--".wholeMatch(of: pattern) == nil)
    #expect("field name".wholeMatch(of: pattern) == nil)
    #expect("123start".wholeMatch(of: pattern) == nil)
}
```

- [ ] **Step 2: Run tests**

```bash
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -destination "platform=macOS,arch=arm64" test
```

- [ ] **Step 3: Commit**

```bash
git add SwiftUI/EdgeStudioUnitTests/Models/AttachmentTests.swift
git commit -m "test(attachments/swiftui): add delete attachment flow tests"
```

---

### Task 13: Run full test suites on both platforms

- [ ] **Step 1: Run .NET tests**

```bash
cd dotnet/src && dotnet build EdgeStudio.sln && dotnet test EdgeStudioTests/EdgeStudioTests.csproj
```

- [ ] **Step 2: Run SwiftUI tests**

```bash
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -destination "platform=macOS,arch=arm64" test
```

- [ ] **Step 3: Build SwiftUI for iOS**

```bash
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M5)" build
```

All builds and tests must pass.
