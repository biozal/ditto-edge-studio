using EdgeStudio.Controls;
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;
using FluentAssertions;
using System.Collections.Generic;
using Xunit;

namespace EdgeStudioTests;

public class PresenceGraphAnimatorTests
{
    private static PresenceGraphSnapshot MakeSnapshot(string localKey, params string[] peerKeys)
    {
        var nodes = new List<PresenceNode>
        {
            new(localKey, "Me", true, false, false, null)
        };
        var edges = new List<PresenceEdge>();
        foreach (var pk in peerKeys)
        {
            nodes.Add(new PresenceNode(pk, pk, false, false, false, null));
            edges.Add(new PresenceEdge(localKey, pk, "Bluetooth", $"{localKey}_{pk}"));
        }
        return new PresenceGraphSnapshot(nodes, edges, localKey);
    }

    [Fact]
    public void UpdateLayout_NewNodes_CreatesAppearingStates()
    {
        var animator = new PresenceGraphAnimator();
        var positions = new Dictionary<string, NodePosition>
        {
            ["me"] = new(0, 0),
            ["peer1"] = new(100, 0),
            ["peer2"] = new(0, 100)
        };
        var snapshot = MakeSnapshot("me", "peer1", "peer2");

        animator.UpdateLayout(positions, snapshot);

        animator.NodeStates.Should().HaveCount(3);
        animator.NodeStates["peer1"].Phase.Should().Be(AnimationPhase.Appearing);
        animator.NodeStates["me"].Phase.Should().Be(AnimationPhase.Appearing);
    }

    [Fact]
    public void UpdateLayout_RemovedNodes_BeginDisappearing()
    {
        var animator = new PresenceGraphAnimator();

        var positions1 = new Dictionary<string, NodePosition>
        {
            ["me"] = new(0, 0),
            ["peer1"] = new(100, 0),
            ["peer2"] = new(0, 100)
        };
        animator.UpdateLayout(positions1, MakeSnapshot("me", "peer1", "peer2"));

        for (int i = 0; i < 120; i++)
            animator.Tick(1f / 60f);

        var positions2 = new Dictionary<string, NodePosition>
        {
            ["me"] = new(0, 0),
            ["peer1"] = new(100, 0)
        };
        animator.UpdateLayout(positions2, MakeSnapshot("me", "peer1"));

        animator.NodeStates["peer2"].Phase.Should().Be(AnimationPhase.Disappearing);
    }

    [Fact]
    public void UpdateLayout_ExistingNodes_UpdatesTarget()
    {
        var animator = new PresenceGraphAnimator();
        var positions1 = new Dictionary<string, NodePosition>
        {
            ["me"] = new(0, 0),
            ["peer1"] = new(100, 0)
        };
        animator.UpdateLayout(positions1, MakeSnapshot("me", "peer1"));

        for (int i = 0; i < 120; i++)
            animator.Tick(1f / 60f);

        var positions2 = new Dictionary<string, NodePosition>
        {
            ["me"] = new(0, 0),
            ["peer1"] = new(200, 0)
        };
        animator.UpdateLayout(positions2, MakeSnapshot("me", "peer1"));

        animator.NodeStates["peer1"].TargetX.Should().Be(200);
    }

    [Fact]
    public void Tick_RemovesGoneNodes()
    {
        var animator = new PresenceGraphAnimator();
        var positions = new Dictionary<string, NodePosition>
        {
            ["me"] = new(0, 0),
            ["peer1"] = new(100, 0)
        };
        animator.UpdateLayout(positions, MakeSnapshot("me", "peer1"));

        for (int i = 0; i < 120; i++)
            animator.Tick(1f / 60f);

        var positions2 = new Dictionary<string, NodePosition>
        {
            ["me"] = new(0, 0)
        };
        animator.UpdateLayout(positions2, MakeSnapshot("me"));

        for (int i = 0; i < 120; i++)
            animator.Tick(1f / 60f);

        animator.NodeStates.Should().NotContainKey("peer1");
    }

    [Fact]
    public void IsAnimating_TrueWhileNodesInMotion()
    {
        var animator = new PresenceGraphAnimator();
        var positions = new Dictionary<string, NodePosition>
        {
            ["me"] = new(0, 0),
            ["peer1"] = new(100, 0)
        };
        animator.UpdateLayout(positions, MakeSnapshot("me", "peer1"));

        animator.IsAnimating.Should().BeTrue();

        for (int i = 0; i < 120; i++)
            animator.Tick(1f / 60f);

        animator.IsAnimating.Should().BeFalse();
    }

    [Fact]
    public void GetEffectivePositions_ReturnsAnimatedPositions()
    {
        var animator = new PresenceGraphAnimator();
        var positions = new Dictionary<string, NodePosition>
        {
            ["me"] = new(0, 0),
            ["peer1"] = new(100, 0)
        };
        animator.UpdateLayout(positions, MakeSnapshot("me", "peer1"));

        var effective = animator.GetEffectivePositions();
        effective.Should().ContainKey("me");
        effective.Should().ContainKey("peer1");

        // peer1 should be at start position (0,0) — hasn't ticked yet
        effective["peer1"].X.Should().Be(0);
    }
}
