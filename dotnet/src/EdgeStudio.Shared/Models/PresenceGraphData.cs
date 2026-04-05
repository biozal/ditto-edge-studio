// EdgeStudio.Shared/Models/PresenceGraphData.cs
using System.Collections.Generic;
using System.Linq;

namespace EdgeStudio.Shared.Models;

/// <summary>
/// A node in the presence graph — represents a peer device or synthetic cloud node.
/// </summary>
public sealed record PresenceNode(
    string PeerKey,
    string DeviceName,
    bool IsLocal,
    bool IsCloudNode,
    bool IsConnectedToCloud,
    string? Os);

/// <summary>
/// An edge in the presence graph — a connection between two peers via a transport.
/// </summary>
public sealed record PresenceEdge(
    string PeerKey1,
    string PeerKey2,
    string ConnectionType,
    string ConnectionId)
{
    /// <summary>
    /// Normalized key for deduplication: sorted peer keys + type.
    /// SDK returns A→B and B→A as separate objects.
    /// </summary>
    public string NormalizedPairKey
    {
        get
        {
            var sorted = string.CompareOrdinal(PeerKey1, PeerKey2) <= 0
                ? (PeerKey1, PeerKey2)
                : (PeerKey2, PeerKey1);
            return $"{sorted.Item1}_{sorted.Item2}_{ConnectionType}";
        }
    }
}

/// <summary>
/// Immutable snapshot of the full presence graph topology at a point in time.
/// </summary>
public sealed class PresenceGraphSnapshot
{
    public IReadOnlyList<PresenceNode> Nodes { get; }
    public IReadOnlyList<PresenceEdge> AllEdges { get; }
    public string LocalPeerKey { get; }

    /// <summary>
    /// Edges after removing bidirectional duplicates (A→B and B→A collapsed to one).
    /// </summary>
    public IReadOnlyList<PresenceEdge> DeduplicatedEdges { get; }

    public PresenceGraphSnapshot(
        IReadOnlyList<PresenceNode> nodes,
        IReadOnlyList<PresenceEdge> allEdges,
        string localPeerKey)
    {
        Nodes = nodes;
        AllEdges = allEdges;
        LocalPeerKey = localPeerKey;

        DeduplicatedEdges = allEdges
            .GroupBy(e => e.NormalizedPairKey)
            .Select(g => g.First())
            .ToList();
    }

    /// <summary>
    /// Returns a filtered snapshot containing only directly connected peers
    /// (peers with at least one edge where localPeerKey is an endpoint).
    /// </summary>
    public PresenceGraphSnapshot FilterToDirectConnections()
    {
        var directEdges = DeduplicatedEdges
            .Where(e => e.PeerKey1 == LocalPeerKey || e.PeerKey2 == LocalPeerKey)
            .ToList();

        var directPeerKeys = directEdges
            .SelectMany(e => new[] { e.PeerKey1, e.PeerKey2 })
            .Distinct()
            .ToHashSet();

        var directNodes = Nodes
            .Where(n => n.IsLocal || directPeerKeys.Contains(n.PeerKey))
            .ToList();

        return new PresenceGraphSnapshot(directNodes, directEdges, LocalPeerKey);
    }
}
