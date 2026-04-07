namespace EdgeStudio.Shared.Messages;

/// <summary>
/// Sent when the user requests to add an attachment to a document from the context menu.
/// Carries the JSON of the target document.
/// </summary>
public record AddAttachmentRequestedMessage(string DocumentJson, string Collection, string QueryMode);

/// <summary>
/// Sent after an attachment is successfully linked to a document.
/// </summary>
public record AttachmentAddedMessage(string DocumentId, string FieldName, string Collection);

/// <summary>
/// Sent when the user requests to delete attachment field(s) from a document.
/// </summary>
public record DeleteAttachmentRequestedMessage(string DocumentJson, string Collection, string QueryMode);

/// <summary>
/// Sent to update the attachment progress indicator.
/// </summary>
public record AttachmentProgressMessage(bool IsActive, string Message, double FractionCompleted);
