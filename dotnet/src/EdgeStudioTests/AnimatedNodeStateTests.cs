using EdgeStudio.Controls;
using EdgeStudio.Shared.Services;
using FluentAssertions;
using Xunit;

namespace EdgeStudioTests;

public class AnimatedNodeStateTests
{
    [Fact]
    public void NewNode_StartsAtPhase_Appearing()
    {
        var state = AnimatedNodeState.CreateAppearing(
            peerKey: "peer1",
            targetPosition: new NodePosition(100, 200));

        state.Phase.Should().Be(AnimationPhase.Appearing);
        state.Opacity.Should().Be(0f);
        state.Scale.Should().Be(0.5f);
        state.CurrentX.Should().Be(0);
        state.CurrentY.Should().Be(0);
    }

    [Fact]
    public void Tick_Appearing_InterpolatesOpacityAndScale()
    {
        var state = AnimatedNodeState.CreateAppearing(
            peerKey: "peer1",
            targetPosition: new NodePosition(100, 0));

        state.Tick(0.2f);

        state.Opacity.Should().BeGreaterThan(0f);
        state.Scale.Should().BeGreaterThan(0.5f);
        state.CurrentX.Should().BeGreaterThan(0);
    }

    [Fact]
    public void Tick_Appearing_CompletesToVisible()
    {
        var state = AnimatedNodeState.CreateAppearing(
            peerKey: "peer1",
            targetPosition: new NodePosition(100, 200));

        for (int i = 0; i < 60; i++)
            state.Tick(1f / 60f);

        state.Phase.Should().Be(AnimationPhase.Visible);
        state.Opacity.Should().BeApproximately(1f, 0.01f);
        state.Scale.Should().BeApproximately(1f, 0.01f);
        state.CurrentX.Should().BeApproximately(100f, 1.0f);
        state.CurrentY.Should().BeApproximately(200f, 1.0f);
    }

    [Fact]
    public void SetTarget_UpdatesTargetPosition()
    {
        var state = AnimatedNodeState.CreateAppearing(
            peerKey: "peer1",
            targetPosition: new NodePosition(100, 200));

        for (int i = 0; i < 60; i++)
            state.Tick(1f / 60f);

        state.SetTarget(new NodePosition(300, 400));

        state.TargetX.Should().Be(300);
        state.TargetY.Should().Be(400);
        state.Phase.Should().Be(AnimationPhase.Visible);
    }

    [Fact]
    public void BeginDisappearing_SetsPhaseAndTarget()
    {
        var state = AnimatedNodeState.CreateAppearing(
            peerKey: "peer1",
            targetPosition: new NodePosition(100, 200));

        for (int i = 0; i < 60; i++)
            state.Tick(1f / 60f);

        state.BeginDisappearing();

        state.Phase.Should().Be(AnimationPhase.Disappearing);
        state.TargetX.Should().Be(0);
        state.TargetY.Should().Be(0);
    }

    [Fact]
    public void Tick_Disappearing_CompletesToGone()
    {
        var state = AnimatedNodeState.CreateAppearing(
            peerKey: "peer1",
            targetPosition: new NodePosition(100, 200));

        for (int i = 0; i < 60; i++)
            state.Tick(1f / 60f);

        state.BeginDisappearing();

        for (int i = 0; i < 60; i++)
            state.Tick(1f / 60f);

        state.Phase.Should().Be(AnimationPhase.Gone);
        state.Opacity.Should().BeLessThan(0.05f);
    }

    [Fact]
    public void IsAnimating_TrueWhileNotConverged()
    {
        var state = AnimatedNodeState.CreateAppearing(
            peerKey: "peer1",
            targetPosition: new NodePosition(100, 200));

        state.IsAnimating.Should().BeTrue();

        for (int i = 0; i < 120; i++)
            state.Tick(1f / 60f);

        state.IsAnimating.Should().BeFalse();
    }
}
