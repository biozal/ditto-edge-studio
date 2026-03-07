using System;
using System.Runtime.InteropServices;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using SukiUI.Controls;
using ZXing;
using ZXing.QrCode;

namespace EdgeStudio.Views
{
    public partial class QrCodeDisplayWindow : SukiWindow
    {
        private readonly string _payload;

        public QrCodeDisplayWindow(string payload, string databaseName)
        {
            InitializeComponent();
            _payload = payload;
            Title = databaseName;
            DatabaseNameText.Text = databaseName;
            QrImage.Source = GenerateQrBitmap(payload);
        }

        private void CopyPayload_Click(object? sender, RoutedEventArgs e)
        {
            _ = Clipboard?.SetTextAsync(_payload);
        }

        private void Close_Click(object? sender, RoutedEventArgs e) => Close();

        private static WriteableBitmap GenerateQrBitmap(string payload)
        {
            var writer = new BarcodeWriterPixelData
            {
                Format = BarcodeFormat.QR_CODE,
                Options = new QrCodeEncodingOptions
                {
                    Height = 300,
                    Width = 300,
                    Margin = 2
                }
            };

            var pixelData = writer.Write(payload);

            var bitmap = new WriteableBitmap(
                new PixelSize(pixelData.Width, pixelData.Height),
                new Vector(96, 96),
                PixelFormat.Bgra8888,
                AlphaFormat.Opaque);

            using var fb = bitmap.Lock();
            Marshal.Copy(pixelData.Pixels, 0, fb.Address, pixelData.Pixels.Length);

            return bitmap;
        }
    }
}
