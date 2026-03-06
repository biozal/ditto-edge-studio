namespace EdgeStudio.Shared.Models;

/// <summary>
/// Defines the three distinct types of peer cards.
/// </summary>
public enum PeerCardType
{
    /// <summary>The local device running Edge Studio</summary>
    Local,

    /// <summary>A remote peer device in the Ditto mesh</summary>
    Remote,

    /// <summary>A Ditto cloud server</summary>
    Server
}
