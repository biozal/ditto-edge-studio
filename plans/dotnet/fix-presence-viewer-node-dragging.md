# Fix Presence Viewer Node Dragging (Dotnet)

## Problem

In the dotnet presence viewer, clicking and dragging anywhere on the graph pans the entire diagram. Individual peer nodes cannot be dragged to reposition them. This differs from the SwiftUI version where:

- Clicking a peer node and dragging moves **that node only** (with connection lines updating in real-time)
- Clicking empty space and dragging **pans the viewport**

## Root Cause

`PresenceGraphControl.cs` has no hit testing. `OnPointerPressed` always sets `_isPanning = true` regardless of what was clicked. There is no concept of selecting or dragging individual nodes.

The `Positions` dictionary comes from `NetworkLayoutEngine.ComputeLayout()` and is treated as read-only — there's no mechanism to override individual node positions after layout.

## SwiftUI Reference Implementation

In `PresenceNetworkScene.swift` (SpriteKit-based):

1. **`mouseDown`**: Hit tests with `nodes(at: location)` to find if a `PeerNode` was clicked
   - If node found: sets `selectedNode`, `isDraggingNode = true`, highlights node (1.1x scale)
   - If empty space: sets `isPanning = true`
2. **`mouseDragged`**: 
   - If dragging node: updates `node.position` directly, calls `updateConnectionsForNode()` to redraw lines
   - If panning: moves camera by event delta
3. **`mouseUp`**: Clears selection, removes highlights
4. **Layout deferral**: Sets `isUserInteracting = true` during drag to prevent layout engine from resetting positions

## Implementation Plan

### Step 1: Add hit testing to `PresenceGraphControl.cs`

Add a method to convert screen coordinates to graph coordinates and check if they fall within a node's pill rectangle.

```csharp
// New fields
private string? _draggedNodeKey;
private bool _isDraggingNode;
private Dictionary<string, NodePosition>? _positionOverrides; // user-dragged positions

private string? HitTestNode(Point screenPos)
{
    // Convert screen position to graph coordinates:
    // graphX = (screenX - width/2 - panX) / zoom
    // graphY = (screenY - height/2 - panY) / zoom
    // Then check each node's pill rect (same sizing as renderer: textWidth + 24 wide, 28 tall)
}
```

### Step 2: Modify pointer event handlers

Update `OnPointerPressed`:
```csharp
protected override void OnPointerPressed(PointerPressedEventArgs e)
{
    if (e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
    {
        var pos = e.GetPosition(this);
        var hitNodeKey = HitTestNode(pos);
        
        if (hitNodeKey != null)
        {
            // Start node drag
            _isDraggingNode = true;
            _draggedNodeKey = hitNodeKey;
            _positionOverrides ??= new();
        }
        else
        {
            // Start viewport pan
            _isPanning = true;
        }
        _lastPointerPos = pos;
        e.Handled = true;
    }
}
```

Update `OnPointerMoved`:
```csharp
protected override void OnPointerMoved(PointerEventArgs e)
{
    if (_isDraggingNode && _draggedNodeKey != null)
    {
        var pos = e.GetPosition(this);
        // Convert screen delta to graph-space delta (divide by zoom)
        // Update the node's position in _positionOverrides
        // Call InvalidateVisual() to redraw with new position
    }
    else if (_isPanning)
    {
        // Existing pan logic
    }
}
```

Update `OnPointerReleased`:
```csharp
protected override void OnPointerReleased(PointerReleasedEventArgs e)
{
    _isPanning = false;
    _isDraggingNode = false;
    _draggedNodeKey = null;
}
```

### Step 3: Add position override support

The control needs to merge layout-computed positions with user-dragged overrides. Two approaches:

**Option A (Simpler — recommended):** Maintain `_positionOverrides` dictionary inside `PresenceGraphControl`. When rendering, merge overrides on top of the bound `Positions`. When layout recomputes (new peer joins/leaves), clear overrides for removed peers but keep overrides for peers that still exist.

**Option B (ViewModel-aware):** Push dragged positions back to the ViewModel. More complex, requires two-way binding. Not needed for this feature.

Implementation for Option A:
```csharp
private Dictionary<string, NodePosition> GetEffectivePositions()
{
    var positions = Positions;
    if (positions == null) return new();
    if (_positionOverrides == null || _positionOverrides.Count == 0) return positions;
    
    var effective = new Dictionary<string, NodePosition>(positions);
    foreach (var (key, pos) in _positionOverrides)
    {
        if (effective.ContainsKey(key))
            effective[key] = pos;
    }
    return effective;
}
```

Update `Render()` to use `GetEffectivePositions()` instead of `Positions` directly.

### Step 4: Handle node pill sizing for hit testing

The hit test needs to know each node's pill width, which depends on the text label. Two approaches:

**Option A (Recalculate):** Compute pill width during hit test using the same font/sizing as the renderer (11pt font, textWidth + 24px padding, 28px height).

**Option B (Cache from renderer):** Have the renderer return node bounds after drawing. More complex coupling.

**Recommend Option A** — it's self-contained and the calculation is cheap (one `MeasureText` per node during hit test, only on click).

### Step 5: Clear overrides on topology change

When `Positions` property changes (new layout from ViewModel), prune `_positionOverrides` to only keep entries for nodes that still exist:

```csharp
protected override void OnPropertyChanged(AvaloniaPropertyChangedEventArgs change)
{
    base.OnPropertyChanged(change);
    if (change.Property == PositionsProperty)
    {
        PruneOverrides();
    }
}

private void PruneOverrides()
{
    if (_positionOverrides == null || Positions == null) return;
    var keysToRemove = _positionOverrides.Keys
        .Where(k => !Positions.ContainsKey(k)).ToList();
    foreach (var key in keysToRemove)
        _positionOverrides.Remove(key);
}
```

### Step 6 (Optional Enhancement): Visual feedback on hover/drag

Match the SwiftUI version's visual feedback:
- **Hover**: Change cursor to hand when over a node (requires `PointerMoved` hit testing)
- **Drag highlight**: Draw the dragged node slightly larger (1.1x scale) or with a glow/border

This can be done by passing the `_draggedNodeKey` and/or `_hoveredNodeKey` to the renderer, which applies a different fill or scale for that node.

### Step 7: Add `ResetView()` update

The existing `ResetView()` method should also clear position overrides:
```csharp
public void ResetView()
{
    _zoom = 1.0f;
    _panX = 0;
    _panY = 0;
    _positionOverrides?.Clear();
    ZoomLevel = 1.0f;
    InvalidateVisual();
}
```

## Files to Modify

| File | Changes |
|------|---------|
| `Controls/PresenceGraphControl.cs` | Hit testing, node dragging, position overrides, cursor feedback |
| `Controls/PresenceGraphRenderer.cs` | Accept optional highlighted node key for visual feedback (minor) |

## Files NOT Modified

- `PresenceViewerViewModel.cs` — no changes needed (position overrides are view-level state)
- `NetworkLayoutEngine.cs` — no changes needed
- `PresenceGraphData.cs` — no changes needed

## Testing

1. Click and drag a peer node — it should move independently, connection lines follow
2. Click and drag empty space — viewport pans as before
3. Scroll wheel — zoom works as before
4. New peer joins mesh — layout updates, previously dragged nodes keep their overrides
5. Peer disconnects — its override is pruned
6. Reset view button — clears all overrides and returns to computed layout
7. Verify in both light and dark themes (SkiaSharp rendering is theme-independent)

## Complexity

Low-medium. All changes are contained in `PresenceGraphControl.cs` with a minor optional change to the renderer. No architectural changes needed.
