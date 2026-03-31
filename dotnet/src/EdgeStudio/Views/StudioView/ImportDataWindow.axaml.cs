using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Data.Repositories;
using EdgeStudio.Shared.Messages;
using SukiUI.Controls;

namespace EdgeStudio.Views.StudioView
{
    public partial class ImportDataWindow : SukiWindow
    {
        private readonly IImportService _importService;
        private readonly ICollectionsRepository _collectionsRepository;
        private string? _selectedFilePath;
        private bool _isImporting;

        public ImportDataWindow(
            IImportService importService,
            ICollectionsRepository collectionsRepository)
        {
            InitializeComponent();
            _importService = importService;
            _collectionsRepository = collectionsRepository;
            Opened += OnWindowOpened;
        }

        private async void OnWindowOpened(object? sender, EventArgs e)
        {
            await LoadCollectionsAsync();
        }

        private async Task LoadCollectionsAsync()
        {
            try
            {
                // Load collections into the ComboBox by triggering a refresh and reading them
                var collections = new System.Collections.ObjectModel.ObservableCollection<EdgeStudio.Shared.Models.CollectionInfo>();
                _collectionsRepository.RegisterObserver(collections, _ => { });

                // Give the observer a moment to populate
                await Task.Delay(500);

                await Dispatcher.UIThread.InvokeAsync(() =>
                {
                    var names = collections.Select(c => c.Name).OrderBy(n => n).ToList();
                    CollectionComboBox.ItemsSource = names;
                    if (names.Count > 0)
                        CollectionComboBox.SelectedIndex = 0;
                });
            }
            catch
            {
                // Silently continue — user can type a new collection name
            }
        }

        private async void ChooseFile_Click(object? sender, RoutedEventArgs e)
        {
            try
            {
                var topLevel = GetTopLevel(this);
                if (topLevel == null) return;

                var files = await topLevel.StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
                {
                    Title = "Select JSON File",
                    AllowMultiple = false,
                    FileTypeFilter = new[]
                    {
                        new FilePickerFileType("JSON Files") { Patterns = new[] { "*.json" } }
                    }
                });

                if (files.Count == 0) return;

                _selectedFilePath = files[0].Path.LocalPath;
                FileNameText.Text = Path.GetFileName(_selectedFilePath);
                FileNameText.Opacity = 1.0;
            }
            catch (Exception ex)
            {
                ShowStatus($"Error selecting file: {ex.Message}", isError: true);
            }
        }

        private void CollectionToggle_Click(object? sender, RoutedEventArgs e)
        {
            var useExisting = ExistingCollectionRadio.IsChecked == true;
            CollectionComboBox.IsVisible = useExisting;
            NewCollectionTextBox.IsVisible = !useExisting;
        }

        private async void Import_Click(object? sender, RoutedEventArgs e)
        {
            if (_isImporting) return;

            if (string.IsNullOrEmpty(_selectedFilePath))
            {
                ShowStatus("Please select a JSON file first.", isError: true);
                return;
            }

            var collectionName = ExistingCollectionRadio.IsChecked == true
                ? CollectionComboBox.SelectedItem?.ToString()
                : NewCollectionTextBox.Text?.Trim();

            if (string.IsNullOrWhiteSpace(collectionName))
            {
                ShowStatus("Please specify a target collection.", isError: true);
                return;
            }

            _isImporting = true;
            ImportButton.IsEnabled = false;
            ChooseFileButton.IsEnabled = false;

            try
            {
                var jsonContent = await File.ReadAllTextAsync(_selectedFilePath);

                // Validate first
                int docCount;
                try
                {
                    docCount = _importService.ValidateJson(jsonContent);
                }
                catch (InvalidOperationException ex)
                {
                    ShowStatus(ex.Message, isError: true);
                    return;
                }

                ShowStatus($"Importing {docCount} document(s)...", isError: false);
                ImportProgressBar.IsVisible = true;
                ImportProgressBar.Maximum = docCount;
                ImportProgressBar.Value = 0;

                var useInitial = InitialInsertToggle.IsChecked == true;

                var result = await Task.Run(() =>
                    _importService.ImportAsync(jsonContent, collectionName, useInitial,
                        progress => Dispatcher.UIThread.Post(() =>
                        {
                            ImportProgressBar.Value = progress.Current;
                            var msg = progress.CurrentDocumentId != null
                                ? $"Importing {progress.Current}/{progress.Total}: {progress.CurrentDocumentId}"
                                : $"Importing {progress.Current}/{progress.Total}...";
                            StatusText.Text = msg;
                        })));

                ImportProgressBar.IsVisible = false;

                if (result.FailureCount == 0)
                {
                    ShowStatus($"Successfully imported {result.SuccessCount} document(s) into '{collectionName}'.", isError: false);
                    ImportButton.Content = "Done";
                    ImportButton.Click -= Import_Click;
                    ImportButton.Click += (_, _) => Close();
                }
                else
                {
                    var errorSummary = $"Imported {result.SuccessCount}, failed {result.FailureCount}.";
                    if (result.Errors.Count > 0)
                        errorSummary += $"\nFirst error: {result.Errors[0]}";
                    ShowStatus(errorSummary, isError: true);
                }

                // Signal collections to refresh so new data appears immediately
                WeakReferenceMessenger.Default.Send(new RefreshCollectionsRequestedMessage());
            }
            catch (Exception ex)
            {
                ImportProgressBar.IsVisible = false;
                ShowStatus($"Import failed: {ex.Message}", isError: true);
            }
            finally
            {
                _isImporting = false;
                ImportButton.IsEnabled = true;
                ChooseFileButton.IsEnabled = true;
            }
        }

        private void Cancel_Click(object? sender, RoutedEventArgs e)
        {
            Close();
        }

        private void ShowStatus(string message, bool isError)
        {
            StatusPanel.IsVisible = true;
            StatusText.Text = message;
            // Use theme-safe opacity styling rather than hardcoded colors
            StatusText.Opacity = isError ? 1.0 : 0.8;
            StatusText.FontWeight = isError
                ? Avalonia.Media.FontWeight.SemiBold
                : Avalonia.Media.FontWeight.Normal;
        }
    }
}
