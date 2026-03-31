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

namespace EdgeStudio.Controls;

/// <summary>
/// Avalonia custom control that renders the presence graph using SkiaSharp via WriteableBitmap.
/// Supports zoom (scroll wheel) and pan (click-drag on empty space).
/// </summary>
public class PresenceGraphControl : Control
{
    private WriteableBitmap? _bitmap;
    private readonly PresenceGraphRenderer _renderer = new();

    private float _zoom = 1.0f;
    private float _panX = 0;
    private float _panY = 0;
    private Point _lastPointerPos;
    private bool _isPanning;

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
            _zoom = change.GetNewValue<float>();
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
            var positions = Positions;

            if (snapshot != null && positions != null)
                _renderer.Render(canvas, pixelWidth, pixelHeight, snapshot, positions, _zoom, _panX, _panY);
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
            _isPanning = true;
            _lastPointerPos = e.GetPosition(this);
            e.Handled = true;
        }
    }

    protected override void OnPointerMoved(PointerEventArgs e)
    {
        base.OnPointerMoved(e);
        if (_isPanning)
        {
            var pos = e.GetPosition(this);
            _panX += (float)(pos.X - _lastPointerPos.X);
            _panY += (float)(pos.Y - _lastPointerPos.Y);
            _lastPointerPos = pos;
            InvalidateVisual();
            e.Handled = true;
        }
    }

    protected override void OnPointerReleased(PointerReleasedEventArgs e)
    {
        base.OnPointerReleased(e);
        _isPanning = false;
    }

    public void ResetView()
    {
        _zoom = 1.0f;
        _panX = 0;
        _panY = 0;
        ZoomLevel = 1.0f;
        InvalidateVisual();
    }
}
