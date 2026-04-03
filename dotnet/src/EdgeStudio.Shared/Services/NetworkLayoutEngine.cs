// EdgeStudio.Shared/Services/NetworkLayoutEngine.cs
using System;
using System.Collections.Generic;
using System.Linq;
using EdgeStudio.Shared.Models;

namespace EdgeStudio.Shared.Services;

public readonly record struct NodePosition(double X, double Y);

public static class NetworkLayoutEngine
{
    private const double BaseRadius = 124.0;
    private const double RingIncrement = 101.0;

    public static Dictionary<string, NodePosition> ComputeLayout(PresenceGraphSnapshot snapshot)
    {
        var positions = new Dictionary<string, NodePosition>();
        if (snapshot.Nodes.Count == 0) return positions;

        var adjacency = BuildAdjacency(snapshot);
        var rings = AssignRings(snapshot.LocalPeerKey, adjacency, snapshot.Nodes);

        if (rings.TryGetValue(snapshot.LocalPeerKey, out _))
            positions[snapshot.LocalPeerKey] = new NodePosition(0, 0);

        var peersByRing = rings
            .Where(kv => kv.Key != snapshot.LocalPeerKey)
            .GroupBy(kv => kv.Value)
            .OrderBy(g => g.Key)
            .ToList();

        foreach (var ringGroup in peersByRing)
        {
            var ring = ringGroup.Key;
            var peers = ringGroup.Select(kv => kv.Key).ToList();

            if (ring == 1)
                peers = OrderRing1Peers(peers, adjacency);

            var radius = ComputeRingRadius(ring, peers.Count);
            var angleStep = 2 * Math.PI / Math.Max(peers.Count, 1);
            var startAngle = Math.PI / 2;

            for (int i = 0; i < peers.Count; i++)
            {
                var angle = startAngle + i * angleStep;
                positions[peers[i]] = new NodePosition(radius * Math.Cos(angle), radius * Math.Sin(angle));
            }
        }

        return positions;
    }

    private static Dictionary<string, HashSet<string>> BuildAdjacency(PresenceGraphSnapshot snapshot)
    {
        var adj = new Dictionary<string, HashSet<string>>();
        foreach (var node in snapshot.Nodes)
            adj[node.PeerKey] = new HashSet<string>();

        foreach (var edge in snapshot.DeduplicatedEdges)
        {
            if (adj.ContainsKey(edge.PeerKey1) && adj.ContainsKey(edge.PeerKey2))
            {
                adj[edge.PeerKey1].Add(edge.PeerKey2);
                adj[edge.PeerKey2].Add(edge.PeerKey1);
            }
        }
        return adj;
    }

    private static Dictionary<string, int> AssignRings(string localPeerKey, Dictionary<string, HashSet<string>> adjacency, IReadOnlyList<PresenceNode> nodes)
    {
        var rings = new Dictionary<string, int>();
        var queue = new Queue<string>();

        if (adjacency.ContainsKey(localPeerKey))
        {
            rings[localPeerKey] = 0;
            queue.Enqueue(localPeerKey);
        }

        while (queue.Count > 0)
        {
            var current = queue.Dequeue();
            var currentRing = rings[current];
            foreach (var neighbor in adjacency[current])
            {
                if (!rings.ContainsKey(neighbor))
                {
                    rings[neighbor] = currentRing + 1;
                    queue.Enqueue(neighbor);
                }
            }
        }

        var maxRing = rings.Values.DefaultIfEmpty(0).Max();
        foreach (var node in nodes)
        {
            if (!rings.ContainsKey(node.PeerKey))
                rings[node.PeerKey] = maxRing + 1;
        }
        return rings;
    }

    private static List<string> OrderRing1Peers(List<string> peers, Dictionary<string, HashSet<string>> adjacency)
    {
        if (peers.Count <= 2) return peers;

        var ring1Set = new HashSet<string>(peers);
        var ring1Adj = peers.ToDictionary(
            p => p,
            p => adjacency.TryGetValue(p, out var neighbors) ? neighbors.Where(n => ring1Set.Contains(n)).ToHashSet() : new HashSet<string>());

        var used = new HashSet<string>();
        var result = new LinkedList<string>();
        var start = peers.OrderByDescending(p => ring1Adj[p].Count).First();
        result.AddFirst(start);
        used.Add(start);

        while (used.Count < peers.Count)
        {
            var addedAny = false;
            var front = result.First!.Value;
            var frontNeighbor = ring1Adj[front].Where(n => !used.Contains(n)).OrderByDescending(n => ring1Adj[n].Count).FirstOrDefault();
            if (frontNeighbor != null) { result.AddFirst(frontNeighbor); used.Add(frontNeighbor); addedAny = true; }

            var back = result.Last!.Value;
            var backNeighbor = ring1Adj[back].Where(n => !used.Contains(n)).OrderByDescending(n => ring1Adj[n].Count).FirstOrDefault();
            if (backNeighbor != null) { result.AddLast(backNeighbor); used.Add(backNeighbor); addedAny = true; }

            if (!addedAny) { var remaining = peers.First(p => !used.Contains(p)); result.AddLast(remaining); used.Add(remaining); }
        }
        return result.ToList();
    }

    private static double ComputeRingRadius(int ring, int peerCount)
    {
        var baseR = BaseRadius + (ring - 1) * RingIncrement;
        var minRadius = peerCount * 80.0 / (2 * Math.PI);
        return Math.Max(baseR, minRadius);
    }
}
