// EdgeStudio/Controls/PresenceGraphAnimator.cs
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;
using System.Collections.Generic;
using System.Linq;

namespace EdgeStudio.Controls;

/// <summary>
/// Manages animated state for all nodes in the presence graph.
/// Diffs incoming layout positions against current nodes to create
/// appear/disappear/reposition animations.
/// </summary>
public class PresenceGraphAnimator
{
    public Dictionary<string, AnimatedNodeState> NodeStates { get; } = new();

    public bool IsAnimating => NodeStates.Values.Any(s => s.IsAnimating);

    public void UpdateLayout(Dictionary<string, NodePosition> positions, PresenceGraphSnapshot snapshot)
    {
        var newKeys = positions.Keys.ToHashSet();
        var existingKeys = NodeStates.Keys.ToHashSet();

        // Nodes to add (new peers)
        foreach (var key in newKeys.Except(existingKeys))
        {
            NodeStates[key] = AnimatedNodeState.CreateAppearing(key, positions[key]);
        }

        // Nodes to remove (departed peers)
        foreach (var key in existingKeys.Except(newKeys))
        {
            if (NodeStates[key].Phase != AnimationPhase.Disappearing
                && NodeStates[key].Phase != AnimationPhase.Gone)
            {
                NodeStates[key].BeginDisappearing();
            }
        }

        // Existing nodes — update target position
        foreach (var key in newKeys.Intersect(existingKeys))
        {
            var state = NodeStates[key];
            if (state.Phase == AnimationPhase.Disappearing || state.Phase == AnimationPhase.Gone)
            {
                // Node was disappearing but came back — recreate as appearing
                NodeStates[key] = AnimatedNodeState.CreateAppearing(key, positions[key]);
            }
            else
            {
                state.SetTarget(positions[key]);
            }
        }
    }

    public void Tick(float deltaTime)
    {
        var keysToRemove = new List<string>();

        foreach (var (key, state) in NodeStates)
        {
            state.Tick(deltaTime);
            if (state.Phase == AnimationPhase.Gone)
                keysToRemove.Add(key);
        }

        foreach (var key in keysToRemove)
            NodeStates.Remove(key);
    }

    public Dictionary<string, NodePosition> GetEffectivePositions()
    {
        var result = new Dictionary<string, NodePosition>();
        foreach (var (key, state) in NodeStates)
        {
            if (state.Phase != AnimationPhase.Gone)
                result[key] = new NodePosition(state.CurrentX, state.CurrentY);
        }
        return result;
    }

    public void Clear()
    {
        NodeStates.Clear();
    }
}
