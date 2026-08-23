using Avalonia.Controls;
using EdgeStudio.Shared.Models;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;

namespace EdgeStudio.Views;

public partial class DeleteAttachmentWindow : Window
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
