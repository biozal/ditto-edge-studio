namespace EdgeStudio.Shared.Messages
{
    /// <summary>
    /// Sent when a QR code display window should be shown for a database config.
    /// </summary>
    public record ShowQrCodeMessage(string Payload, string DatabaseName);

    /// <summary>
    /// Sent when the QR code import window should be shown.
    /// </summary>
    public record ShowQrCodeImportMessage();
}
