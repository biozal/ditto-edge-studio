// EdgeStudioTests/PresenceGraphDataTests.cs
using EdgeStudio.Shared.Models;
using FluentAssertions;

namespace EdgeStudioTests;

public class PresenceGraphDataTests
{
    [Fact]
    public void PresenceNode_ShouldStoreProperties()
    {
        var node = new PresenceNode(
            PeerKey: "abc123",
            DeviceName: "iPhone",
            IsLocal: true,
            IsCloudNode: false,
            IsConnectedToCloud: false,
            Os: "iOS");

        node.PeerKey.Should().Be("abc123");
        node.DeviceName.Should().Be("iPhone");
        node.IsLocal.Should().BeTrue();
    }

    [Fact]
    public void PresenceEdge_NormalizedPairKey_ShouldBeConsistent()
    {
        var edge1 = new PresenceEdge("a", "b", "Bluetooth", "conn1");
        var edge2 = new PresenceEdge("b", "a", "Bluetooth", "conn2");

        edge1.NormalizedPairKey.Should().Be(edge2.NormalizedPairKey);
    }

    [Fact]
    public void PresenceEdge_NormalizedPairKey_DifferentTypes_ShouldDiffer()
    {
        var edge1 = new PresenceEdge("a", "b", "Bluetooth", "conn1");
        var edge2 = new PresenceEdge("a", "b", "WebSocket", "conn2");

        edge1.NormalizedPairKey.Should().NotBe(edge2.NormalizedPairKey);
    }

    [Fact]
    public void PresenceGraphSnapshot_ShouldDeduplicateEdges()
    {
        var nodes = new List<PresenceNode>
        {
            new("local", "Me", true, false, false, "macOS"),
            new("remote1", "Phone", false, false, false, "iOS")
        };
        var edges = new List<PresenceEdge>
        {
            new("local", "remote1", "Bluetooth", "c1"),
            new("remote1", "local", "Bluetooth", "c2") // duplicate direction
        };

        var snapshot = new PresenceGraphSnapshot(nodes, edges, "local");
        snapshot.DeduplicatedEdges.Should().HaveCount(1);
    }

    [Fact]
    public void FilterToDirectConnections_ShouldExcludeMultihopPeers()
    {
        var nodes = new List<PresenceNode>
        {
            new("local", "Me", true, false, false, "macOS"),
            new("peer1", "Phone", false, false, false, "iOS"),
            new("peer2", "Server", false, false, false, "Linux")
        };
        var edges = new List<PresenceEdge>
        {
            new("local", "peer1", "Bluetooth", "c1"),
            new("peer1", "peer2", "WebSocket", "c2") // peer2 only via peer1
        };

        var snapshot = new PresenceGraphSnapshot(nodes, edges, "local");
        var filtered = snapshot.FilterToDirectConnections();

        filtered.Nodes.Should().HaveCount(2);
        filtered.Nodes.Should().NotContain(n => n.PeerKey == "peer2");
        filtered.DeduplicatedEdges.Should().HaveCount(1);
    }
}
