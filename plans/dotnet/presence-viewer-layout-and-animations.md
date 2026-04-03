# Presence Viewer: Layout Fix & Animation System (Dotnet)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix peer node overlapping in Direct Only mode and add smooth appear/disappear/reposition animations to match the SwiftUI SpriteKit version's visual quality.

**Architecture:** The dotnet Presence Viewer renders via SkiaSharp onto an Avalonia `WriteableBitmap`. Since there's no built-in scene graph or animation framework (unlike SpriteKit), we'll build a lightweight per-node animation state system driven by a `DispatcherTimer`. Each node tracks animated position, opacity, and scale. When the layout engine produces new target positions, nodes interpolate smoothly toward them. New nodes fade in from the center; departing nodes fade out toward the center. The renderer already draws per-node — we pass the animated state through so it can apply opacity/scale per node.

**Tech Stack:** C# / .NET 10.0, SkiaSharp, Avalonia UI `DispatcherTimer`

---

## Problem Analysis

### Issue 1: Overlapping Peers in Direct Only Mode

**Root cause:** `NetworkLayoutEngine.ComputeRingRadius()` uses `peerCount * 30.0 / (2 * Math.PI)` as the minimum radius. The actual pill width is `textWidth + 24px` (typically 70-120px per node). With 7 peers on ring 1, the minimum circumference is `7 * 30 = 210px` — but the actual visual space needed is `7 * 100 ≈ 700px`. The base radius of 124px gives circumference `2π * 124 ≈ 779px`, which is barely enough and breaks when pill labels are long.

**Fix:** Increase the per-peer spacing factor from `30.0` to `80.0` (matching SwiftUI's `peerDiameter: 60.0 + 20.0` spacing). Also add an `OrderRing1Peers` connection-aware sort (already exists but uses a basic greedy algorithm — keep it, just fix spacing).

### Issue 2: No Animations

**Root cause:** The renderer draws a static frame from `Dictionary<string, NodePosition>`. When the ViewModel recalculates positions, the entire graph jumps instantly.

**Fix:** Introduce `AnimatedNodeState` per peer that tracks current animated position/opacity/scale and target values. A `DispatcherTimer` ticks at ~60fps, interpolating animated values toward targets. The renderer reads animated state instead of raw layout positions.

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| **Modify** | `EdgeStudio.Shared/Services/NetworkLayoutEngine.cs` | Fix `ComputeRingRadius` spacing constant |
| **Create** | `EdgeStudio/Controls/AnimatedNodeState.cs` | Per-node animation state (position, opacity, scale, phase) |
| **Create** | `EdgeStudio/Controls/PresenceGraphAnimator.cs` | Timer-driven animation loop, manages node state lifecycle |
| **Modify** | `EdgeStudio/Controls/PresenceGraphControl.cs` | Integrate animator, pass animated state to renderer |
| **Modify** | `EdgeStudio/Controls/PresenceGraphRenderer.cs` | Accept per-node opacity/scale, apply during draw |
| **Modify** | `EdgeStudio/ViewModels/PresenceViewerViewModel.cs` | No changes needed (positions still flow as `Dictionary<string, NodePosition>`) |
| **Modify** | `EdgeStudioTests/NetworkLayoutEngineTests.cs` | Update spacing expectations |
| **Create** | `EdgeStudioTests/AnimatedNodeStateTests.cs` | Test interpolation logic |
| **Create** | `EdgeStudioTests/PresenceGraphAnimatorTests.cs` | Test node lifecycle (add/remove/reposition) |

---

## Task 1: Fix Layout Engine Spacing

**Files:**
- Modify: `dotnet/src/EdgeStudio.Shared/Services/NetworkLayoutEngine.cs:137-143`
- Modify: `dotnet/src/EdgeStudioTests/NetworkLayoutEngineTests.cs`

The per-peer spacing factor is too small, causing pills to overlap when several peers sit on ring 1.

- [ ] **Step 1: Update `ComputeRingRadius` spacing constant**

In `NetworkLayoutEngine.cs`, change line 140:

```csharp
// Before:
var minRadius = peerCount * 30.0 / (2 * Math.PI);

// After:
var minRadius = peerCount * 80.0 / (2 * Math.PI);
```

This matches the SwiftUI layout engine which uses `peerDiameter: 60.0 + 20.0 spacing = 80.0` per peer on the circumference.

- [ ] **Step 2: Build to verify no compile errors**

Run:
```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```
Expected: Build succeeded.

- [ ] **Step 3: Update existing layout tests for new spacing**

Open `EdgeStudioTests/NetworkLayoutEngineTests.cs`. Any test that asserts on minimum radius values from `ComputeRingRadius` will need adjustment. The new minimum radius for N peers is `N * 80 / (2π)` instead of `N * 30 / (2π)`. For example, 7 peers now need minimum radius `7 * 80 / 6.28 ≈ 89.2` (up from `33.4`). The base radius is `124.0`, so for 7 or fewer ring-1 peers, the base radius still wins — but for larger peer counts the minimum will kick in sooner.

Check all tests that assert distances between peer positions and update expected values if any now fail due to radius expansion.

- [ ] **Step 4: Run tests**

Run:
```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --no-build --verbosity normal
```
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio && git add dotnet/src/EdgeStudio.Shared/Services/NetworkLayoutEngine.cs dotnet/src/EdgeStudioTests/NetworkLayoutEngineTests.cs
git commit -m "fix(dotnet): increase presence viewer peer spacing to prevent overlap

Increase per-peer spacing factor in ComputeRingRadius from 30px to 80px,
matching SwiftUI's peerDiameter(60) + spacing(20). Prevents pill-shaped
nodes from overlapping when many peers sit on ring 1 in Direct Only mode.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Create AnimatedNodeState

**Files:**
- Create: `dotnet/src/EdgeStudio/Controls/AnimatedNodeState.cs`
- Create: `dotnet/src/EdgeStudioTests/AnimatedNodeStateTests.cs`

This class holds per-node animation properties (current position, target position, opacity, scale) and provides a `Tick(deltaTime)` method that interpolates toward targets using exponential easing.

- [ ] **Step 1: Write the AnimatedNodeState tests**

Create `dotnet/src/EdgeStudioTests/AnimatedNodeStateTests.cs`:

```csharp
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

        // Tick with a large enough dt to make progress
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

        // Tick many times to fully converge
        for (int i = 0; i < 60; i++)
            state.Tick(1f / 60f);

        state.Phase.Should().Be(AnimationPhase.Visible);
        state.Opacity.Should().BeApproximately(1f, 0.01f);
        state.Scale.Should().BeApproximately(1f, 0.01f);
        state.CurrentX.Should().BeApproximately(100, 1.0);
        state.CurrentY.Should().BeApproximately(200, 1.0);
    }

    [Fact]
    public void SetTarget_UpdatesTargetPosition()
    {
        var state = AnimatedNodeState.CreateAppearing(
            peerKey: "peer1",
            targetPosition: new NodePosition(100, 200));

        // Complete appearing
        for (int i = 0; i < 60; i++)
            state.Tick(1f / 60f);

        // Move to new target
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

        // Complete appearing
        for (int i = 0; i < 60; i++)
            state.Tick(1f / 60f);

        state.BeginDisappearing();

        state.Phase.Should().Be(AnimationPhase.Disappearing);
        state.TargetX.Should().Be(0); // moves toward center
        state.TargetY.Should().Be(0);
    }

    [Fact]
    public void Tick_Disappearing_CompletesToGone()
    {
        var state = AnimatedNodeState.CreateAppearing(
            peerKey: "peer1",
            targetPosition: new NodePosition(100, 200));

        // Complete appearing
        for (int i = 0; i < 60; i++)
            state.Tick(1f / 60f);

        state.BeginDisappearing();

        // Tick to completion
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --filter "FullyQualifiedName~AnimatedNodeStateTests" --verbosity normal
```
Expected: FAIL — `AnimatedNodeState` type does not exist.

- [ ] **Step 3: Implement AnimatedNodeState**

Create `dotnet/src/EdgeStudio/Controls/AnimatedNodeState.cs`:

```csharp
// EdgeStudio/Controls/AnimatedNodeState.cs
using EdgeStudio.Shared.Services;
using System;

namespace EdgeStudio.Controls;

public enum AnimationPhase
{
    Appearing,
    Visible,
    Disappearing,
    Gone
}

/// <summary>
/// Per-node animation state. Tracks current and target position, opacity, scale.
/// Call Tick(dt) each frame to interpolate toward targets using exponential easing.
/// </summary>
public class AnimatedNodeState
{
    private const float LerpSpeed = 8f; // Higher = faster convergence
    private const float ConvergenceThreshold = 0.5f; // Position snap threshold
    private const float OpacityThreshold = 0.01f;

    public string PeerKey { get; }
    public AnimationPhase Phase { get; private set; }

    // Current animated values (what the renderer reads)
    public float CurrentX { get; private set; }
    public float CurrentY { get; private set; }
    public float Opacity { get; private set; }
    public float Scale { get; private set; }

    // Targets
    public float TargetX { get; private set; }
    public float TargetY { get; private set; }
    private float _targetOpacity;
    private float _targetScale;

    public bool IsAnimating
    {
        get
        {
            if (Phase == AnimationPhase.Gone) return false;
            return MathF.Abs(CurrentX - TargetX) > ConvergenceThreshold
                || MathF.Abs(CurrentY - TargetY) > ConvergenceThreshold
                || MathF.Abs(Opacity - _targetOpacity) > OpacityThreshold
                || MathF.Abs(Scale - _targetScale) > OpacityThreshold;
        }
    }

    private AnimatedNodeState(string peerKey)
    {
        PeerKey = peerKey;
    }

    /// <summary>
    /// Create a node that fades in from the center (0,0) to the target position.
    /// </summary>
    public static AnimatedNodeState CreateAppearing(string peerKey, NodePosition targetPosition)
    {
        return new AnimatedNodeState(peerKey)
        {
            Phase = AnimationPhase.Appearing,
            CurrentX = 0, CurrentY = 0,
            Opacity = 0f, Scale = 0.5f,
            TargetX = (float)targetPosition.X,
            TargetY = (float)targetPosition.Y,
            _targetOpacity = 1f, _targetScale = 1f
        };
    }

    /// <summary>
    /// Create a node already at its final position (for initial scene setup).
    /// </summary>
    public static AnimatedNodeState CreateVisible(string peerKey, NodePosition position)
    {
        return new AnimatedNodeState(peerKey)
        {
            Phase = AnimationPhase.Visible,
            CurrentX = (float)position.X,
            CurrentY = (float)position.Y,
            Opacity = 1f, Scale = 1f,
            TargetX = (float)position.X,
            TargetY = (float)position.Y,
            _targetOpacity = 1f, _targetScale = 1f
        };
    }

    /// <summary>
    /// Update target position (e.g., when layout recalculates).
    /// </summary>
    public void SetTarget(NodePosition newTarget)
    {
        TargetX = (float)newTarget.X;
        TargetY = (float)newTarget.Y;
    }

    /// <summary>
    /// Begin fade-out toward center.
    /// </summary>
    public void BeginDisappearing()
    {
        Phase = AnimationPhase.Disappearing;
        TargetX = 0;
        TargetY = 0;
        _targetOpacity = 0f;
        _targetScale = 0.5f;
    }

    /// <summary>
    /// Advance animation by deltaTime seconds using exponential lerp.
    /// </summary>
    public void Tick(float deltaTime)
    {
        if (Phase == AnimationPhase.Gone) return;

        var t = 1f - MathF.Exp(-LerpSpeed * deltaTime);

        CurrentX += (TargetX - CurrentX) * t;
        CurrentY += (TargetY - CurrentY) * t;
        Opacity += (_targetOpacity - Opacity) * t;
        Scale += (_targetScale - Scale) * t;

        // Snap when close enough
        if (!IsAnimating)
        {
            CurrentX = TargetX;
            CurrentY = TargetY;
            Opacity = _targetOpacity;
            Scale = _targetScale;

            if (Phase == AnimationPhase.Appearing)
                Phase = AnimationPhase.Visible;
            else if (Phase == AnimationPhase.Disappearing)
                Phase = AnimationPhase.Gone;
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --filter "FullyQualifiedName~AnimatedNodeStateTests" --verbosity normal
```
Expected: All 7 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio && git add dotnet/src/EdgeStudio/Controls/AnimatedNodeState.cs dotnet/src/EdgeStudioTests/AnimatedNodeStateTests.cs
git commit -m "feat(dotnet): add AnimatedNodeState for per-node animation

Tracks position, opacity, and scale with exponential easing interpolation.
Supports Appearing (fade-in from center), Visible, Disappearing (fade-out
to center), and Gone phases. Foundation for animated presence viewer.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Create PresenceGraphAnimator

**Files:**
- Create: `dotnet/src/EdgeStudio/Controls/PresenceGraphAnimator.cs`
- Create: `dotnet/src/EdgeStudioTests/PresenceGraphAnimatorTests.cs`

The animator manages a collection of `AnimatedNodeState` objects. When new positions arrive from the ViewModel, it diffs against current nodes: new keys get `CreateAppearing`, removed keys get `BeginDisappearing`, existing keys get `SetTarget`. It exposes a `Tick()` method and an `IsAnimating` flag.

- [ ] **Step 1: Write the PresenceGraphAnimator tests**

Create `dotnet/src/EdgeStudioTests/PresenceGraphAnimatorTests.cs`:

```csharp
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

        // Initial: me + peer1 + peer2
        var positions1 = new Dictionary<string, NodePosition>
        {
            ["me"] = new(0, 0),
            ["peer1"] = new(100, 0),
            ["peer2"] = new(0, 100)
        };
        animator.UpdateLayout(positions1, MakeSnapshot("me", "peer1", "peer2"));

        // Converge
        for (int i = 0; i < 120; i++)
            animator.Tick(1f / 60f);

        // Update: peer2 removed
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

        // Converge
        for (int i = 0; i < 120; i++)
            animator.Tick(1f / 60f);

        // Move peer1
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

        // Converge appearing
        for (int i = 0; i < 120; i++)
            animator.Tick(1f / 60f);

        // Remove peer1
        var positions2 = new Dictionary<string, NodePosition>
        {
            ["me"] = new(0, 0)
        };
        animator.UpdateLayout(positions2, MakeSnapshot("me"));

        // Converge disappearing
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

        // peer1 should be animating from (0,0) toward (100,0)
        effective["peer1"].X.Should().Be(0); // hasn't ticked yet
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --filter "FullyQualifiedName~PresenceGraphAnimatorTests" --verbosity normal
```
Expected: FAIL — `PresenceGraphAnimator` type does not exist.

- [ ] **Step 3: Implement PresenceGraphAnimator**

Create `dotnet/src/EdgeStudio/Controls/PresenceGraphAnimator.cs`:

```csharp
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

    /// <summary>
    /// Update with new layout positions. New nodes appear, removed nodes disappear,
    /// existing nodes reposition smoothly.
    /// </summary>
    public void UpdateLayout(Dictionary<string, NodePosition> positions, PresenceGraphSnapshot snapshot)
    {
        var newKeys = positions.Keys.ToHashSet();
        var existingKeys = NodeStates.Keys.ToHashSet();

        // Nodes to add (new peers)
        foreach (var key in newKeys.Except(existingKeys))
        {
            NodeStates[key] = AnimatedNodeState.CreateAppearing(key, positions[key]);
        }

        // Nodes to remove (departed peers) — only if not already disappearing
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

    /// <summary>
    /// Advance all animations by deltaTime seconds. Removes Gone nodes.
    /// </summary>
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

    /// <summary>
    /// Returns current animated positions for all visible/animating nodes.
    /// Used by the renderer instead of raw layout positions.
    /// </summary>
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

    /// <summary>
    /// Clear all animation state (used when resetting view).
    /// </summary>
    public void Clear()
    {
        NodeStates.Clear();
    }
}
```

- [ ] **Step 4: Build and run tests**

Run:
```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --filter "FullyQualifiedName~PresenceGraphAnimatorTests" --verbosity normal
```
Expected: All 6 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio && git add dotnet/src/EdgeStudio/Controls/PresenceGraphAnimator.cs dotnet/src/EdgeStudioTests/PresenceGraphAnimatorTests.cs
git commit -m "feat(dotnet): add PresenceGraphAnimator for node lifecycle management

Manages per-node AnimatedNodeState. Diffs incoming layout positions to
create appear/reposition/disappear transitions. Removes completed Gone
nodes on tick. Foundation for animated rendering in PresenceGraphControl.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Update Renderer to Support Per-Node Opacity and Scale

**Files:**
- Modify: `dotnet/src/EdgeStudio/Controls/PresenceGraphRenderer.cs:77-97,188-250`

The renderer currently draws all nodes at full opacity and scale 1.0. We need to pass per-node animation state so appearing/disappearing nodes render with correct opacity and scale. Connection lines also need opacity based on their endpoint nodes.

- [ ] **Step 1: Add nodeStates parameter to Render and DrawNodes**

In `PresenceGraphRenderer.cs`, update the `Render` method signature and pass the state through:

```csharp
public void Render(
    SKCanvas canvas, float width, float height,
    PresenceGraphSnapshot snapshot,
    Dictionary<string, NodePosition> positions,
    float zoom, float panX, float panY,
    string? highlightedNodeKey = null,
    Dictionary<string, AnimatedNodeState>? nodeStates = null)
{
    canvas.Clear(SKColors.Transparent);
    if (snapshot.Nodes.Count == 0) return;

    canvas.Save();
    canvas.Translate(width / 2 + panX, height / 2 + panY);
    canvas.Scale(zoom);

    DrawEdges(canvas, snapshot, positions, nodeStates);
    DrawNodes(canvas, snapshot, positions, highlightedNodeKey, nodeStates);

    canvas.Restore();

    DrawLegend(canvas, width, height, snapshot);
}
```

- [ ] **Step 2: Update DrawNodes to apply per-node opacity and scale**

In the `DrawNodes` method, after calculating `scale` and before drawing, look up the node's animation state:

```csharp
private void DrawNodes(SKCanvas canvas, PresenceGraphSnapshot snapshot,
    Dictionary<string, NodePosition> positions, string? highlightedNodeKey,
    Dictionary<string, AnimatedNodeState>? nodeStates)
{
    using var nodeFont = new SKFont(SKTypeface.Default, 11f);
    using var textPaint = new SKPaint { Color = SKColors.White, IsAntialias = true };

    foreach (var node in snapshot.Nodes)
    {
        if (!positions.TryGetValue(node.PeerKey, out var pos)) continue;

        // Get animation state for this node (if animation is active)
        float nodeOpacity = 1f;
        float nodeScale = 1f;
        if (nodeStates != null && nodeStates.TryGetValue(node.PeerKey, out var animState))
        {
            nodeOpacity = animState.Opacity;
            nodeScale = animState.Scale;
        }

        // Skip fully transparent nodes
        if (nodeOpacity < 0.01f) continue;

        var isHighlighted = node.PeerKey == highlightedNodeKey;
        var fillColor = node.IsLocal ? LocalNodeColor : node.IsCloudNode ? CloudNodeColor : RemoteNodeColor;
        var label = node.IsLocal ? "Me" : TruncateLabel(node.DeviceName, 16);
        var textWidth = nodeFont.MeasureText(label);
        var pillWidth = textWidth + 24f;
        var pillHeight = 28f;
        var cornerRadius = pillHeight / 2;

        // Combine highlight scale with animation scale
        var highlightScale = isHighlighted ? 1.1f : 1.0f;
        var combinedScale = highlightScale * nodeScale;
        var scaledPillWidth = pillWidth * combinedScale;
        var scaledPillHeight = pillHeight * combinedScale;
        var scaledCornerRadius = cornerRadius * combinedScale;

        // Apply node opacity to colors
        var alphaFill = fillColor.WithAlpha((byte)(fillColor.Alpha * nodeOpacity));
        var alphaText = SKColors.White.WithAlpha((byte)(255 * nodeOpacity));

        // Draw glow for highlighted node
        if (isHighlighted && nodeOpacity > 0.5f)
        {
            using var glowPaint = new SKPaint
            {
                Color = fillColor.WithAlpha((byte)(80 * nodeOpacity)),
                IsAntialias = true,
                Style = SKPaintStyle.Fill,
                MaskFilter = SKMaskFilter.CreateBlur(SKBlurStyle.Normal, 6f)
            };
            var glowRect = new SKRect(
                (float)pos.X - scaledPillWidth / 2 - 4, (float)pos.Y - scaledPillHeight / 2 - 4,
                (float)pos.X + scaledPillWidth / 2 + 4, (float)pos.Y + scaledPillHeight / 2 + 4);
            canvas.DrawRoundRect(glowRect, scaledCornerRadius + 4, scaledCornerRadius + 4, glowPaint);
        }

        using var fillPaint = new SKPaint
        {
            Color = alphaFill,
            IsAntialias = true,
            Style = SKPaintStyle.Fill
        };

        var rect = new SKRect(
            (float)pos.X - scaledPillWidth / 2, (float)pos.Y - scaledPillHeight / 2,
            (float)pos.X + scaledPillWidth / 2, (float)pos.Y + scaledPillHeight / 2);
        canvas.DrawRoundRect(rect, scaledCornerRadius, scaledCornerRadius, fillPaint);

        // Draw text with opacity
        using var alphaTextPaint = new SKPaint { Color = alphaText, IsAntialias = true };
        var fontScale = 11f * combinedScale;
        using var scaledFont = new SKFont(SKTypeface.Default, fontScale);
        canvas.DrawText(label, (float)pos.X, (float)pos.Y + 4f * combinedScale,
            SKTextAlign.Center, scaledFont, alphaTextPaint);
    }
}
```

- [ ] **Step 3: Update DrawEdges to apply endpoint opacity to connections**

In `DrawEdges`, look up the opacity of both endpoint nodes. Use the minimum opacity so a connection fades with its endpoints:

```csharp
private void DrawEdges(SKCanvas canvas, PresenceGraphSnapshot snapshot,
    Dictionary<string, NodePosition> positions,
    Dictionary<string, AnimatedNodeState>? nodeStates)
{
    var edgesByPair = snapshot.DeduplicatedEdges
        .GroupBy(e =>
        {
            var sorted = string.CompareOrdinal(e.PeerKey1, e.PeerKey2) <= 0
                ? (e.PeerKey1, e.PeerKey2)
                : (e.PeerKey2, e.PeerKey1);
            return $"{sorted.Item1}_{sorted.Item2}";
        })
        .ToList();

    const float baseOffset = 12f;

    foreach (var group in edgesByPair)
    {
        var edges = group.ToList();
        var count = edges.Count;

        for (int i = 0; i < count; i++)
        {
            var edge = edges[i];
            if (!positions.TryGetValue(edge.PeerKey1, out var pos1) ||
                !positions.TryGetValue(edge.PeerKey2, out var pos2))
                continue;

            // Derive edge opacity from endpoint nodes
            float edgeOpacity = 1f;
            if (nodeStates != null)
            {
                float op1 = nodeStates.TryGetValue(edge.PeerKey1, out var s1) ? s1.Opacity : 1f;
                float op2 = nodeStates.TryGetValue(edge.PeerKey2, out var s2) ? s2.Opacity : 1f;
                edgeOpacity = MathF.Min(op1, op2);
            }
            if (edgeOpacity < 0.01f) continue;

            // ... (rest of edge drawing logic unchanged, but apply edgeOpacity to paint.Color)

            float lineOffset = 0f;
            if (count == 2)
                lineOffset = i == 0 ? baseOffset : -baseOffset;
            else if (count > 2)
                lineOffset = -baseOffset + (2 * baseOffset * i / (count - 1));

            var dx = (float)(pos2.X - pos1.X);
            var dy = (float)(pos2.Y - pos1.Y);
            var len = MathF.Sqrt(dx * dx + dy * dy);
            if (len < 0.001f) continue;

            var perpX = -dy / len * lineOffset;
            var perpY = dx / len * lineOffset;

            var fromX = (float)pos1.X + perpX;
            var fromY = (float)pos1.Y + perpY;
            var toX = (float)pos2.X + perpX;
            var toY = (float)pos2.Y + perpY;

            var midX = (fromX + toX) / 2;
            var midY = (fromY + toY) / 2;
            var isLocalEdge = edge.PeerKey1 == snapshot.LocalPeerKey || edge.PeerKey2 == snapshot.LocalPeerKey;
            if (!isLocalEdge)
            {
                var curveAmount = MathF.Min(len * 0.25f, 90f);
                var midLen = MathF.Sqrt(midX * midX + midY * midY);
                if (midLen > 1f)
                {
                    midX += midX / midLen * curveAmount;
                    midY += midY / midLen * curveAmount;
                }
            }

            var isCloudEdge = edge.PeerKey1 == "ditto-cloud-node" || edge.PeerKey2 == "ditto-cloud-node";
            var colorKey = isCloudEdge ? "Cloud" : NormalizeConnectionType(edge.ConnectionType);
            var color = ConnectionColors.GetValueOrDefault(colorKey, DefaultEdgeColor);
            var dashes = DashPatterns.GetValueOrDefault(colorKey);

            // Apply edge opacity
            color = color.WithAlpha((byte)(color.Alpha * edgeOpacity));

            using var paint = new SKPaint
            {
                Color = color,
                StrokeWidth = 2f,
                IsAntialias = true,
                Style = SKPaintStyle.Stroke,
                PathEffect = dashes != null ? SKPathEffect.CreateDash(dashes, 0) : null
            };

            using var path = new SKPath();
            path.MoveTo(fromX, fromY);
            path.QuadTo(midX, midY, toX, toY);
            canvas.DrawPath(path, paint);
        }
    }
}
```

- [ ] **Step 4: Build to verify**

Run:
```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```
Expected: Build succeeded.

- [ ] **Step 5: Run all tests**

Run:
```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --verbosity normal
```
Expected: All tests pass (renderer tests still work since `nodeStates` defaults to `null`).

- [ ] **Step 6: Commit**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio && git add dotnet/src/EdgeStudio/Controls/PresenceGraphRenderer.cs
git commit -m "feat(dotnet): add per-node opacity and scale to presence graph renderer

DrawNodes applies animation opacity/scale per node. DrawEdges derives
edge opacity from endpoint node opacity (min of both). Fully transparent
nodes and edges are skipped. Backward compatible — null nodeStates
renders at full opacity as before.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Integrate Animator into PresenceGraphControl

**Files:**
- Modify: `dotnet/src/EdgeStudio/Controls/PresenceGraphControl.cs`

This is the integration task — wire the animator into the control's lifecycle. When `Positions` or `Snapshot` change, feed the animator. Start a `DispatcherTimer` for the animation loop. Pass animated state to the renderer.

- [ ] **Step 1: Add animator and timer fields**

At the top of `PresenceGraphControl`, add:

```csharp
private readonly PresenceGraphAnimator _animator = new();
private Avalonia.Threading.DispatcherTimer? _animationTimer;
private DateTime _lastTickTime = DateTime.UtcNow;
```

- [ ] **Step 2: Start/stop animation timer based on animation state**

Add methods to manage the timer:

```csharp
private void StartAnimationTimer()
{
    if (_animationTimer != null) return;
    _lastTickTime = DateTime.UtcNow;
    _animationTimer = new Avalonia.Threading.DispatcherTimer
    {
        Interval = TimeSpan.FromMilliseconds(16) // ~60fps
    };
    _animationTimer.Tick += OnAnimationTick;
    _animationTimer.Start();
}

private void StopAnimationTimer()
{
    if (_animationTimer == null) return;
    _animationTimer.Stop();
    _animationTimer.Tick -= OnAnimationTick;
    _animationTimer = null;
}

private void OnAnimationTick(object? sender, EventArgs e)
{
    var now = DateTime.UtcNow;
    var dt = (float)(now - _lastTickTime).TotalSeconds;
    _lastTickTime = now;

    // Clamp dt to prevent large jumps (e.g., after system sleep)
    dt = MathF.Min(dt, 0.1f);

    _animator.Tick(dt);
    InvalidateVisual();

    if (!_animator.IsAnimating)
        StopAnimationTimer();
}
```

- [ ] **Step 3: Feed animator when Positions/Snapshot change**

Update `OnPropertyChanged`:

```csharp
protected override void OnPropertyChanged(AvaloniaPropertyChangedEventArgs change)
{
    base.OnPropertyChanged(change);
    if (change.Property == ZoomLevelProperty)
    {
        _zoom = change.GetNewValue<float>();
    }
    else if (change.Property == PositionsProperty || change.Property == SnapshotProperty)
    {
        PruneOverrides();
        FeedAnimator();
    }
}

private void FeedAnimator()
{
    var positions = Positions;
    var snapshot = Snapshot;
    if (positions == null || snapshot == null) return;

    _animator.UpdateLayout(positions, snapshot);
    StartAnimationTimer();
}
```

- [ ] **Step 4: Update GetEffectivePositions to use animated positions**

Replace the existing `GetEffectivePositions` method:

```csharp
private Dictionary<string, NodePosition> GetEffectivePositions()
{
    // Start with animated positions (or raw positions if no animation)
    var positions = _animator.NodeStates.Count > 0
        ? _animator.GetEffectivePositions()
        : Positions ?? new Dictionary<string, NodePosition>();

    // Apply user-dragged overrides on top
    if (_positionOverrides != null && _positionOverrides.Count > 0)
    {
        var effective = new Dictionary<string, NodePosition>(positions);
        foreach (var (key, pos) in _positionOverrides)
        {
            if (effective.ContainsKey(key))
                effective[key] = pos;
        }
        return effective;
    }

    return positions;
}
```

- [ ] **Step 5: Pass nodeStates to renderer in Render method**

In the `Render` method, update the renderer call:

```csharp
if (snapshot != null && positions.Count > 0)
    _renderer.Render(canvas, pixelWidth, pixelHeight, snapshot, positions, _zoom, _panX, _panY,
        highlightedNodeKey: _draggedNodeKey ?? _hoveredNodeKey,
        nodeStates: _animator.NodeStates.Count > 0 ? _animator.NodeStates : null);
```

- [ ] **Step 6: Clear animator on ResetView**

Update `ResetView`:

```csharp
public void ResetView()
{
    _zoom = 1.0f;
    _panX = 0;
    _panY = 0;
    _positionOverrides?.Clear();
    _animator.Clear();
    StopAnimationTimer();
    ZoomLevel = 1.0f;
    InvalidateVisual();
}
```

- [ ] **Step 7: Build and test**

Run:
```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --verbosity normal
```
Expected: Build succeeded, all tests pass.

- [ ] **Step 8: Commit**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio && git add dotnet/src/EdgeStudio/Controls/PresenceGraphControl.cs
git commit -m "feat(dotnet): integrate animation system into presence graph control

Wire PresenceGraphAnimator into PresenceGraphControl. DispatcherTimer
ticks at ~60fps during animations, driving smooth transitions. Nodes
fade in from center, reposition smoothly, and fade out when departing.
Timer auto-stops when all animations converge.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Handle Snapshot Changes for Disappearing Nodes

**Files:**
- Modify: `dotnet/src/EdgeStudio/Controls/PresenceGraphControl.cs`
- Modify: `dotnet/src/EdgeStudio/Controls/PresenceGraphRenderer.cs`

When a peer disconnects, the `Snapshot` from the ViewModel no longer includes that node — but the animator still has it in `Disappearing` phase. The renderer needs to draw disappearing nodes too, not just nodes in the snapshot.

- [ ] **Step 1: Build a combined snapshot for rendering**

In `PresenceGraphControl.Render`, before calling the renderer, create an extended snapshot that includes disappearing nodes:

```csharp
// In the Render method, before the _renderer.Render call:
// Build extended snapshot that includes disappearing nodes
var renderSnapshot = snapshot;
if (_animator.NodeStates.Count > 0)
{
    var disappearingNodes = _animator.NodeStates
        .Where(kv => kv.Value.Phase == AnimationPhase.Disappearing
            && !snapshot.Nodes.Any(n => n.PeerKey == kv.Key))
        .Select(kv => new PresenceNode(kv.Key, kv.Key, false, false, false, null))
        .ToList();

    if (disappearingNodes.Count > 0)
    {
        var allNodes = snapshot.Nodes.Concat(disappearingNodes).ToList();
        renderSnapshot = new PresenceGraphSnapshot(allNodes, snapshot.AllEdges, snapshot.LocalPeerKey);
    }
}
```

Pass `renderSnapshot` instead of `snapshot` to the renderer.

- [ ] **Step 2: Add required using statements**

Add at the top of `PresenceGraphControl.cs`:

```csharp
using EdgeStudio.Shared.Models;
```

(This should already be there but verify. `PresenceNode` and `PresenceGraphSnapshot` constructors are needed.)

- [ ] **Step 3: Build and test**

Run:
```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --verbosity normal
```
Expected: Build succeeded, all tests pass.

- [ ] **Step 4: Commit**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio && git add dotnet/src/EdgeStudio/Controls/PresenceGraphControl.cs
git commit -m "fix(dotnet): render disappearing nodes during fade-out animation

Build extended snapshot that includes nodes in Disappearing phase so
the renderer draws them with decreasing opacity. Without this, peers
would vanish instantly when removed from the ViewModel snapshot.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Final Integration Test and Polish

**Files:**
- Modify: `dotnet/src/EdgeStudio/Controls/PresenceGraphControl.cs` (if needed)

- [ ] **Step 1: Run full test suite**

Run:
```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio.sln --verbosity minimal && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --verbosity normal
```
Expected: All tests pass, no warnings.

- [ ] **Step 2: Manual verification checklist**

Launch the app and connect to a database with peers:

1. **Direct Only mode (primary focus):**
   - [ ] Toggle "Direct Only" ON
   - [ ] Verify no peers overlap — each pill has clear space around it
   - [ ] With 3-5 peers, ring 1 should be well-spaced
   - [ ] With 7+ peers, ring should expand automatically

2. **Animation — peer appears:**
   - [ ] Connect a new device while watching the viewer
   - [ ] New peer should fade in from center (opacity 0→1, scale 0.5→1.0)
   - [ ] Connection line should fade in with the node
   - [ ] Existing nodes should smoothly reposition to accommodate

3. **Animation — peer disappears:**
   - [ ] Disconnect a device
   - [ ] Departing peer should fade out toward center (opacity 1→0, scale 1.0→0.5)
   - [ ] Connection lines should fade with the departing node
   - [ ] Remaining nodes should smoothly reposition

4. **Animation — layout change:**
   - [ ] Toggle Direct Only on/off
   - [ ] Nodes should smoothly animate to new positions (not jump)

5. **Interaction still works:**
   - [ ] Drag a node — it moves, connections follow
   - [ ] Pan the view — smooth scrolling
   - [ ] Zoom in/out — works correctly
   - [ ] Reset view — clears animations and position overrides

- [ ] **Step 3: Commit any polish fixes**

If any adjustments were needed during manual testing:

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio && git add -A dotnet/src/
git commit -m "polish(dotnet): presence viewer animation and layout adjustments

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Summary of Changes

| Change | Impact |
|--------|--------|
| `ComputeRingRadius` spacing: `30→80` | Prevents peer overlap in Direct Only with many peers |
| `AnimatedNodeState` | Per-node interpolation engine (position, opacity, scale) |
| `PresenceGraphAnimator` | Node lifecycle management (appear/reposition/disappear) |
| `PresenceGraphRenderer` per-node opacity/scale | Smooth visual transitions for all nodes and edges |
| `PresenceGraphControl` timer integration | 60fps animation loop, auto-starts/stops |
| Extended snapshot for disappearing nodes | Departing peers visible during fade-out |

The animation system adds ~250 lines of new code across 2 new files, and ~50 lines of modifications to existing files. No new NuGet dependencies required.
