namespace EdgeStudio.Shared.Messages;

/// <summary>
/// Message sent when transport configuration starts, signaling that sync operations should be paused.
/// </summary>
public class TransportConfigurationStartedMessage
{
}

/// <summary>
/// Message sent when transport configuration completes, signaling that sync operations can resume.
/// </summary>
public class TransportConfigurationCompletedMessage
{
}

/// <summary>
/// Message sent when sync is stopped, signaling that all remote/server peers should be cleared immediately.
/// </summary>
public class SyncStoppedMessage
{
}

/// <summary>
/// Message sent when sync is started, signaling that peer observers should be re-registered.
/// </summary>
public class SyncStartedMessage
{
}
