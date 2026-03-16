using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Media;
using Avalonia.Platform.Storage;
using EdgeStudio.Shared.Data.Repositories;
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;
using SkiaSharp;
using SukiUI.Controls;
using ZXing;

namespace EdgeStudio.Views.Database
{
    public partial class QrCodeImportWindow : SukiWindow
    {
        private readonly IDatabaseRepository _databaseRepository;
        private readonly IFavoritesRepository _favoritesRepository;
        private readonly IQrCodeService _qrCodeService;

        public QrCodeImportWindow(
            IDatabaseRepository databaseRepository,
            IFavoritesRepository favoritesRepository,
            IQrCodeService qrCodeService)
        {
            InitializeComponent();
            _databaseRepository = databaseRepository;
            _favoritesRepository = favoritesRepository;
            _qrCodeService = qrCodeService;
        }

        private async void OpenFile_Click(object? sender, RoutedEventArgs e)
        {
            try
            {
                var topLevel = GetTopLevel(this);
                if (topLevel == null) return;

                var files = await topLevel.StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
                {
                    Title = "Select QR Code Image",
                    AllowMultiple = false,
                    FileTypeFilter = new[]
                    {
                        new FilePickerFileType("Images") { Patterns = new[] { "*.png", "*.jpg", "*.jpeg", "*.bmp" } }
                    }
                });

                if (files.Count == 0) return;

                var filePath = files[0].Path.LocalPath;
                var qrText = DecodeQrFromFile(filePath);

                if (qrText == null)
                {
                    ShowStatus("Could not decode a QR code from the selected image.", isError: true);
                    return;
                }

                await ImportFromPayload(qrText);
            }
            catch (Exception ex)
            {
                ShowStatus($"Error opening file: {ex.Message}", isError: true);
            }
        }

        private async void ImportPaste_Click(object? sender, RoutedEventArgs e)
        {
            var payload = PasteTextBox.Text?.Trim();
            if (string.IsNullOrEmpty(payload))
            {
                ShowStatus("Please enter an EDS2 payload.", isError: true);
                return;
            }
            await ImportFromPayload(payload);
        }

        private async Task ImportFromPayload(string payload)
        {
            try
            {
                var result = _qrCodeService.Decode(payload);
                if (result == null)
                {
                    ShowStatus("Invalid or unrecognized payload. Expected an EDS2 payload.", isError: true);
                    return;
                }

                var (config, favorites) = result.Value;
                await _databaseRepository.AddDittoDatabaseConfig(config);

                foreach (var fav in favorites)
                {
                    await _favoritesRepository.AddQueryHistory(new QueryHistory(
                        Guid.NewGuid().ToString(), fav, DateTime.UtcNow.ToString("O")));
                }

                ShowStatus($"Successfully imported '{config.Name}'.", isError: false);
                // Close after a brief moment so user sees the success message
                await Task.Delay(800);
                Close();
            }
            catch (Exception ex)
            {
                ShowStatus($"Import failed: {ex.Message}", isError: true);
            }
        }

        private static string? DecodeQrFromFile(string filePath)
        {
            try
            {
                using var skBitmap = SKBitmap.Decode(filePath);
                if (skBitmap == null) return null;

                using var rgbBitmap = skBitmap.Copy(SKColorType.Rgba8888);
                var pixels = rgbBitmap.Bytes;

                // Convert RGBA to RGB for ZXing RGBLuminanceSource
                var rgbBytes = new byte[rgbBitmap.Width * rgbBitmap.Height * 3];
                for (int i = 0; i < rgbBitmap.Width * rgbBitmap.Height; i++)
                {
                    rgbBytes[i * 3] = pixels[i * 4];       // R
                    rgbBytes[i * 3 + 1] = pixels[i * 4 + 1]; // G
                    rgbBytes[i * 3 + 2] = pixels[i * 4 + 2]; // B
                }

                var luminance = new RGBLuminanceSource(rgbBytes, rgbBitmap.Width, rgbBitmap.Height);
                var reader = new BarcodeReaderGeneric { Options = { TryHarder = true } };
                var decoded = reader.Decode(luminance);
                return decoded?.Text;
            }
            catch
            {
                return null;
            }
        }

        private void ShowStatus(string message, bool isError)
        {
            StatusText.Text = message;
            StatusText.Foreground = isError
                ? new SolidColorBrush(Avalonia.Media.Color.Parse("#FF8080"))
                : new SolidColorBrush(Avalonia.Media.Color.Parse("#80FF80"));
            StatusText.IsVisible = true;
        }
    }
}
