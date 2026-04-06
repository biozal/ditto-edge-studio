namespace EdgeStudio.Shared.Services;

/// <summary>
/// Service for displaying modal dialogs to the user.
/// Used for errors that require acknowledgment before continuing.
/// </summary>
public interface IDialogService
{
    /// <summary>
    /// Displays a modal error dialog that the user must dismiss.
    /// </summary>
    /// <param name="title">The dialog title</param>
    /// <param name="message">The error message to display</param>
    void ShowError(string title, string message);
}
