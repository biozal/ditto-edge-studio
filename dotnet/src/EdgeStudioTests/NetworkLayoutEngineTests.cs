// EdgeStudioTests/NetworkLayoutEngineTests.cs
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;
using FluentAssertions;

namespace EdgeStudioTests;

public class NetworkLayoutEngineTests
{
    [Fact]
    public void ComputeLayout_LocalPeerOnly_ShouldPlaceAtOrigin()
    {
        var nodes = new List<PresenceNode>
        {
            new("local", "Me", true, false, false, "macOS")
        };
        var snapshot = new PresenceGraphSnapshot(nodes, new List<PresenceEdge>(), "local");
        var positions = NetworkLayoutEngine.ComputeLayout(snapshot);

        positions.Should().ContainKey("local");
        positions["local"].X.Should().BeApproximately(0, 0.01);
        positions["local"].Y.Should().BeApproximately(0, 0.01);
    }

    [Fact]
    public void ComputeLayout_TwoDirectPeers_ShouldPlaceOnRing1()
    {
        var nodes = new List<PresenceNode>
        {
            new("local", "Me", true, false, false, "macOS"),
            new("peer1", "Phone", false, false, false, "iOS"),
            new("peer2", "Tablet", false, false, false, "Android")
        };
        var edges = new List<PresenceEdge>
        {
            new("local", "peer1", "Bluetooth", "c1"),
            new("local", "peer2", "WebSocket", "c2")
        };
        var snapshot = new PresenceGraphSnapshot(nodes, edges, "local");
        var positions = NetworkLayoutEngine.ComputeLayout(snapshot);

        positions.Should().ContainKeys("local", "peer1", "peer2");
        var r1 = Math.Sqrt(positions["peer1"].X * positions["peer1"].X + positions["peer1"].Y * positions["peer1"].Y);
        var r2 = Math.Sqrt(positions["peer2"].X * positions["peer2"].X + positions["peer2"].Y * positions["peer2"].Y);
        r1.Should().BeApproximately(r2, 1.0);
        r1.Should().BeGreaterThan(0);
    }

    [Fact]
    public void ComputeLayout_MultihopPeer_ShouldBeOnOuterRing()
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
            new("peer1", "peer2", "WebSocket", "c2")
        };
        var snapshot = new PresenceGraphSnapshot(nodes, edges, "local");
        var positions = NetworkLayoutEngine.ComputeLayout(snapshot);

        var r1 = Math.Sqrt(positions["peer1"].X * positions["peer1"].X + positions["peer1"].Y * positions["peer1"].Y);
        var r2 = Math.Sqrt(positions["peer2"].X * positions["peer2"].X + positions["peer2"].Y * positions["peer2"].Y);
        r2.Should().BeGreaterThan(r1, "multihop peers should be farther from center");
    }

    [Fact]
    public void ComputeLayout_EmptyGraph_ShouldReturnEmpty()
    {
        var snapshot = new PresenceGraphSnapshot(new List<PresenceNode>(), new List<PresenceEdge>(), "local");
        var positions = NetworkLayoutEngine.ComputeLayout(snapshot);
        positions.Should().BeEmpty();
    }

    [Fact]
    public void ComputeLayout_AllPositions_ShouldBeDeterministic()
    {
        var nodes = new List<PresenceNode>
        {
            new("local", "Me", true, false, false, "macOS"),
            new("peer1", "A", false, false, false, "iOS"),
            new("peer2", "B", false, false, false, "Android"),
            new("peer3", "C", false, false, false, "Linux")
        };
        var edges = new List<PresenceEdge>
        {
            new("local", "peer1", "Bluetooth", "c1"),
            new("local", "peer2", "WebSocket", "c2"),
            new("local", "peer3", "AccessPoint", "c3"),
            new("peer1", "peer2", "Bluetooth", "c4")
        };
        var snapshot = new PresenceGraphSnapshot(nodes, edges, "local");
        var pos1 = NetworkLayoutEngine.ComputeLayout(snapshot);
        var pos2 = NetworkLayoutEngine.ComputeLayout(snapshot);

        foreach (var key in pos1.Keys)
        {
            pos1[key].X.Should().BeApproximately(pos2[key].X, 0.001);
            pos1[key].Y.Should().BeApproximately(pos2[key].Y, 0.001);
        }
    }
}
