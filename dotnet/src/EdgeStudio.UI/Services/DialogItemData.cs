using System;
using System.Collections.Generic;

namespace EdgeStudio.UI.Services;

public record DialogButton(string Label, Action Callback);

public record DialogItemData(
    string Title,
    string Message,
    DialogSeverity Severity,
    List<DialogButton> Buttons);

public enum DialogSeverity
{
    Error,
    Warning,
    Info
}
