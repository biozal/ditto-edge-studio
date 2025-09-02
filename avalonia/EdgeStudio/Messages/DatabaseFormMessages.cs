using System;

namespace EdgeStudio.Messages;

/// <summary>
/// Message sent when the Add Database form should be shown
/// </summary>
public class ShowAddDatabaseFormMessage
{
    // Empty message class - no parameters needed
}

/// <summary>
/// Message sent when the Edit Database form should be shown
/// </summary>
public class ShowEditDatabaseFormMessage
{
    // Empty message class - no parameters needed
}

/// <summary>
/// Message sent when the Database form should be hidden
/// </summary>
public class HideDatabaseFormMessage
{
    // Empty message class - no parameters needed
}

/// <summary>
/// Message sent when an error occurs that should be displayed to the user
/// </summary>
public class ErrorOccurredMessage
{
    public string ErrorMessage { get; }
    
    public ErrorOccurredMessage(string errorMessage)
    {
        ErrorMessage = errorMessage ?? throw new ArgumentNullException(nameof(errorMessage));
    }
}