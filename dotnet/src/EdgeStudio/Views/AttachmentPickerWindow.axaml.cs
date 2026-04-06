using System;
using System.IO;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using SukiUI.Controls;

namespace EdgeStudio.Views;

public partial class AttachmentPickerWindow : SukiWindow
{
    private const long LocalSizeLimit = 10 * 1024 * 1024;  // 10MB
    private const long HttpSizeLimit = 20 * 1024 * 1024;   // 20MB

    public string? SelectedFilePath { get; private set; }
    public string? SelectedFieldName { get; private set; }
    public string? SelectedFileName { get; private set; }
    public string? SelectedMimeType { get; private set; }
    public bool Confirmed { get; private set; }

    private long _selectedFileSize;
    private string _queryMode = "local";

    // Parameterless constructor required for XAML
    public AttachmentPickerWindow()
    {
        InitializeComponent();
        WireEvents();
    }

    public AttachmentPickerWindow(string collection, string documentId, string queryMode)
    {
        InitializeComponent();
        _queryMode = queryMode;

        CollectionText.Text = collection;
        DocumentIdText.Text = documentId;

        WireEvents();
    }

    private void WireEvents()
    {
        ChooseFileButton.Click += OnChooseFile;
        CancelButton.Click += (_, _) => Close();
        AttachButton.Click += OnAttach;
        FieldNameInput.TextChanged += (_, _) => UpdateCanAttach();
    }

    private async void OnChooseFile(object? sender, RoutedEventArgs e)
    {
        try
        {
            var topLevel = GetTopLevel(this);
            if (topLevel == null) return;

            var files = await topLevel.StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
            {
                Title = "Select File to Attach",
                AllowMultiple = false,
                FileTypeFilter = new[]
                {
                    new FilePickerFileType("Images") { Patterns = new[] { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.heic" } },
                    new FilePickerFileType("Text") { Patterns = new[] { "*.txt", "*.md", "*.csv", "*.json", "*.xml", "*.log" } },
                    new FilePickerFileType("Audio") { Patterns = new[] { "*.mp3", "*.wav", "*.m4a", "*.aac", "*.ogg" } },
                    new FilePickerFileType("All Supported") { Patterns = new[] { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.heic", "*.txt", "*.md", "*.csv", "*.json", "*.xml", "*.log", "*.mp3", "*.wav", "*.m4a", "*.aac", "*.ogg" } },
                }
            });

            if (files.Count == 0) return;

            var path = files[0].Path.LocalPath;
            var fileInfo = new FileInfo(path);

            SelectedFilePath = path;
            SelectedFileName = fileInfo.Name;
            _selectedFileSize = fileInfo.Length;
            SelectedMimeType = GetMimeType(fileInfo.Extension.ToLowerInvariant());

            FileInfoText.Text = $"{fileInfo.Name} ({FormatBytes(_selectedFileSize)})";
            FileInfoText.Foreground = null; // reset to default

            UpdateSizeWarning();
            UpdateCanAttach();
        }
        catch (Exception ex)
        {
            FileInfoText.Text = $"Error: {ex.Message}";
        }
    }

    private void OnAttach(object? sender, RoutedEventArgs e)
    {
        SelectedFieldName = FieldNameInput.Text?.Trim();
        Confirmed = true;
        Close();
    }

    private void UpdateCanAttach()
    {
        var hasFile = !string.IsNullOrEmpty(SelectedFilePath);
        var hasFieldName = !string.IsNullOrWhiteSpace(FieldNameInput.Text);
        // Only HTTP mode has a hard limit (20MB). Local mode 10MB is a soft limit (warn only).
        var isOverHardLimit = _queryMode.Equals("http", StringComparison.OrdinalIgnoreCase)
            && _selectedFileSize > HttpSizeLimit;
        // Validate field name: only letters, numbers, underscores
        var isValidFieldName = hasFieldName && System.Text.RegularExpressions.Regex.IsMatch(
            FieldNameInput.Text!.Trim(), @"^[a-zA-Z_][a-zA-Z0-9_]*$");

        AttachButton.IsEnabled = hasFile && isValidFieldName && !isOverHardLimit;
    }

    private void UpdateSizeWarning()
    {
        if (_queryMode.Equals("http", StringComparison.OrdinalIgnoreCase) && _selectedFileSize > HttpSizeLimit)
        {
            SizeWarningText.Text = $"File exceeds the 20 MB HTTP limit ({FormatBytes(_selectedFileSize)}). Choose a smaller file.";
            SizeWarningText.Foreground = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse("Red"));
            SizeWarningText.IsVisible = true;
        }
        else if (!_queryMode.Equals("http", StringComparison.OrdinalIgnoreCase) && _selectedFileSize > LocalSizeLimit)
        {
            SizeWarningText.Text = $"File exceeds the recommended 10 MB local limit ({FormatBytes(_selectedFileSize)}). Performance may be affected.";
            SizeWarningText.Foreground = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse("Orange"));
            SizeWarningText.IsVisible = true;
        }
        else
        {
            SizeWarningText.IsVisible = false;
        }
    }

    private static string GetMimeType(string extension) => extension switch
    {
        ".png" => "image/png",
        ".jpg" or ".jpeg" => "image/jpeg",
        ".gif" => "image/gif",
        ".webp" => "image/webp",
        ".heic" => "image/heic",
        ".txt" => "text/plain",
        ".md" => "text/markdown",
        ".csv" => "text/csv",
        ".json" => "application/json",
        ".xml" => "application/xml",
        ".log" => "text/plain",
        ".mp3" => "audio/mpeg",
        ".wav" => "audio/wav",
        ".m4a" => "audio/mp4",
        ".aac" => "audio/aac",
        ".ogg" => "audio/ogg",
        _ => "application/octet-stream",
    };

    private static string FormatBytes(long bytes)
    {
        if (bytes < 1024) return $"{bytes} B";
        if (bytes < 1024 * 1024) return $"{bytes / 1024.0:F1} KB";
        if (bytes < 1024 * 1024 * 1024) return $"{bytes / (1024.0 * 1024.0):F1} MB";
        return $"{bytes / (1024.0 * 1024.0 * 1024.0):F2} GB";
    }
}
