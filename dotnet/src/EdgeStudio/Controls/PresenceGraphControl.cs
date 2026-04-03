// EdgeStudio/Controls/PresenceGraphControl.cs
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;
using SkiaSharp;
using System;
using System.Collections.Generic;
using System.Linq;

namespace EdgeStudio.Controls;

/// <summary>
/// Avalonia custom control that renders the presence graph using SkiaSharp via WriteableBitmap.
/// Supports zoom (scroll wheel), pan (click-drag on empty space), and individual node dragging.
/// </summary>
public class PresenceGraphControl : Control
{
    private WriteableBitmap? _bitmap;
    private readonly PresenceGraphRenderer _renderer = new();
    private readonly PresenceGraphAnimator _animator = new();
    private Avalonia.Threading.DispatcherTimer? _animationTimer;
    private DateTime _lastTickTime = DateTime.UtcNow;

    private float _zoom = 1.0f;
    private float _panX = 0;
    private float _panY = 0;
    private Point _lastPointerPos;
    private bool _isPanning;

    // Node dragging state
    private string? _draggedNodeKey;
    private bool _isDraggingNode;
    private Dictionary<string, NodePosition>? _positionOverrides;

    // Hover state for cursor feedback
    private string? _hoveredNodeKey;

    public static readonly StyledProperty<PresenceGraphSnapshot?> SnapshotProperty =
        AvaloniaProperty.Register<PresenceGraphControl, PresenceGraphSnapshot?>(nameof(Snapshot));

    public static readonly StyledProperty<Dictionary<string, NodePosition>?> PositionsProperty =
        AvaloniaProperty.Register<PresenceGraphControl, Dictionary<string, NodePosition>?>(nameof(Positions));

    public static readonly StyledProperty<float> ZoomLevelProperty =
        AvaloniaProperty.Register<PresenceGraphControl, float>(nameof(ZoomLevel), 1.0f);

    public PresenceGraphSnapshot? Snapshot
    {
        get => GetValue(SnapshotProperty);
        set => SetValue(SnapshotProperty, value);
    }

    public Dictionary<string, NodePosition>? Positions
    {
        get => GetValue(PositionsProperty);
        set => SetValue(PositionsProperty, value);
    }

    public float ZoomLevel
    {
        get => GetValue(ZoomLevelProperty);
        set => SetValue(ZoomLevelProperty, value);
    }

    static PresenceGraphControl()
    {
        AffectsRender<PresenceGraphControl>(SnapshotProperty, PositionsProperty, ZoomLevelProperty);
    }

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

    /// <summary>
    /// Returns effective positions: layout-computed positions with user-dragged overrides merged on top.
    /// </summary>
    private Dictionary<string, NodePosition> GetEffectivePositions()
    {
        var positions = _animator.NodeStates.Count > 0
            ? _animator.GetEffectivePositions()
            : Positions ?? new Dictionary<string, NodePosition>();

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

    /// <summary>
    /// Removes overrides for nodes that no longer exist in the current layout.
    /// </summary>
    private void PruneOverrides()
    {
        if (_positionOverrides == null || Positions == null) return;
        var keysToRemove = _positionOverrides.Keys
            .Where(k => !Positions.ContainsKey(k)).ToList();
        foreach (var key in keysToRemove)
            _positionOverrides.Remove(key);
    }

    private void FeedAnimator()
    {
        var positions = Positions;
        var snapshot = Snapshot;
        if (positions == null || snapshot == null) return;

        _animator.UpdateLayout(positions, snapshot);
        StartAnimationTimer();
    }

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

        dt = MathF.Min(dt, 0.1f); // Clamp to prevent large jumps

        _animator.Tick(dt);
        InvalidateVisual();

        if (!_animator.IsAnimating)
            StopAnimationTimer();
    }

    /// <summary>
    /// Converts a screen-space point to graph-space coordinates, accounting for pan and zoom.
    /// </summary>
    private (float X, float Y) ScreenToGraph(Point screenPos)
    {
        var bounds = Bounds;
        var graphX = (float)((screenPos.X - bounds.Width / 2 - _panX) / _zoom);
        var graphY = (float)((screenPos.Y - bounds.Height / 2 - _panY) / _zoom);
        return (graphX, graphY);
    }

    /// <summary>
    /// Hit tests the screen position against all node pill rects.
    /// Returns the peer key of the hit node, or null if empty space was clicked.
    /// Uses the same font/sizing as PresenceGraphRenderer.DrawNodes.
    /// </summary>
    private string? HitTestNode(Point screenPos)
    {
        var snapshot = Snapshot;
        var positions = GetEffectivePositions();
        if (snapshot == null || positions.Count == 0) return null;

        var (gx, gy) = ScreenToGraph(screenPos);

        using var nodeFont = new SKFont(SKTypeface.Default, 11f);
        const float pillHeight = 28f;
        const float padding = 24f;
        // Expand hit area slightly for easier clicking
        const float hitPadding = 4f;

        foreach (var node in snapshot.Nodes)
        {
            if (!positions.TryGetValue(node.PeerKey, out var pos)) continue;

            var label = node.IsLocal ? "Me" : TruncateLabel(node.DeviceName, 16);
            var textWidth = nodeFont.MeasureText(label);
            var pillWidth = textWidth + padding;

            var left = (float)pos.X - pillWidth / 2 - hitPadding;
            var right = (float)pos.X + pillWidth / 2 + hitPadding;
            var top = (float)pos.Y - pillHeight / 2 - hitPadding;
            var bottom = (float)pos.Y + pillHeight / 2 + hitPadding;

            if (gx >= left && gx <= right && gy >= top && gy <= bottom)
                return node.PeerKey;
        }

        return null;
    }

    private static string TruncateLabel(string text, int maxLength)
    {
        if (text.Length <= maxLength) return text;
        return text[..(maxLength - 1)] + "\u2026";
    }

    public override void Render(DrawingContext context)
    {
        var bounds = Bounds;
        if (bounds.Width < 1 || bounds.Height < 1) return;

        var pixelWidth = (int)bounds.Width;
        var pixelHeight = (int)bounds.Height;

        if (_bitmap == null || _bitmap.PixelSize.Width != pixelWidth || _bitmap.PixelSize.Height != pixelHeight)
        {
            _bitmap?.Dispose();
            _bitmap = new WriteableBitmap(
                new PixelSize(pixelWidth, pixelHeight),
                new Vector(96, 96),
                PixelFormats.Bgra8888,
                AlphaFormat.Premul);
        }

        using (var lockedBitmap = _bitmap.Lock())
        {
            var info = new SKImageInfo(pixelWidth, pixelHeight, SKColorType.Bgra8888, SKAlphaType.Premul);
            using var surface = SKSurface.Create(info, lockedBitmap.Address, lockedBitmap.RowBytes);
            if (surface == null) return;

            var canvas = surface.Canvas;
            var snapshot = Snapshot;
            var positions = GetEffectivePositions();

            if (snapshot != null && positions.Count > 0)
                _renderer.Render(canvas, pixelWidth, pixelHeight, snapshot, positions, _zoom, _panX, _panY,
                    highlightedNodeKey: _draggedNodeKey ?? _hoveredNodeKey,
                    nodeStates: _animator.NodeStates.Count > 0 ? _animator.NodeStates : null);
            else
                canvas.Clear(SKColors.Transparent);
        }

        context.DrawImage(_bitmap, new Rect(0, 0, bounds.Width, bounds.Height));
    }

    protected override void OnPointerWheelChanged(PointerWheelEventArgs e)
    {
        base.OnPointerWheelChanged(e);
        var delta = (float)e.Delta.Y * 0.1f;
        _zoom = Math.Clamp(_zoom + delta, 0.3f, 3.0f);
        ZoomLevel = _zoom;
        InvalidateVisual();
        e.Handled = true;
    }

    protected override void OnPointerPressed(PointerPressedEventArgs e)
    {
        base.OnPointerPressed(e);
        if (e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
        {
            var pos = e.GetPosition(this);
            var hitNodeKey = HitTestNode(pos);

            if (hitNodeKey != null)
            {
                _isDraggingNode = true;
                _draggedNodeKey = hitNodeKey;
                _positionOverrides ??= new();

                // Initialize override from current effective position if not already overridden
                if (!_positionOverrides.ContainsKey(hitNodeKey))
                {
                    var positions = Positions;
                    if (positions != null && positions.TryGetValue(hitNodeKey, out var currentPos))
                        _positionOverrides[hitNodeKey] = currentPos;
                }
            }
            else
            {
                _isPanning = true;
            }

            _lastPointerPos = pos;
            e.Handled = true;
        }
    }

    protected override void OnPointerMoved(PointerEventArgs e)
    {
        base.OnPointerMoved(e);

        if (_isDraggingNode && _draggedNodeKey != null && _positionOverrides != null)
        {
            var pos = e.GetPosition(this);
            var deltaX = (float)(pos.X - _lastPointerPos.X) / _zoom;
            var deltaY = (float)(pos.Y - _lastPointerPos.Y) / _zoom;

            if (_positionOverrides.TryGetValue(_draggedNodeKey, out var current))
            {
                _positionOverrides[_draggedNodeKey] = new NodePosition(current.X + deltaX, current.Y + deltaY);
            }

            _lastPointerPos = pos;
            InvalidateVisual();
            e.Handled = true;
        }
        else if (_isPanning)
        {
            var pos = e.GetPosition(this);
            _panX += (float)(pos.X - _lastPointerPos.X);
            _panY += (float)(pos.Y - _lastPointerPos.Y);
            _lastPointerPos = pos;
            InvalidateVisual();
            e.Handled = true;
        }
        else
        {
            // Hover hit testing for cursor feedback
            var pos = e.GetPosition(this);
            var hitNodeKey = HitTestNode(pos);
            if (hitNodeKey != _hoveredNodeKey)
            {
                _hoveredNodeKey = hitNodeKey;
                Cursor = hitNodeKey != null ? new Cursor(StandardCursorType.Hand) : Cursor.Default;
                InvalidateVisual();
            }
        }
    }

    protected override void OnPointerReleased(PointerReleasedEventArgs e)
    {
        base.OnPointerReleased(e);
        _isPanning = false;

        if (_isDraggingNode)
        {
            _isDraggingNode = false;
            _draggedNodeKey = null;
            InvalidateVisual();
        }
    }

    protected override void OnPointerExited(PointerEventArgs e)
    {
        base.OnPointerExited(e);
        if (_hoveredNodeKey != null)
        {
            _hoveredNodeKey = null;
            Cursor = Cursor.Default;
            InvalidateVisual();
        }
    }

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
}
