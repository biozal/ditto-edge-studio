// EdgeStudio/Controls/PresenceGraphRenderer.cs
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;
using SkiaSharp;
using System;
using System.Collections.Generic;
using System.Linq;

namespace EdgeStudio.Controls;

/// <summary>
/// Renders the presence graph using SkiaSharp. Draws edges, nodes, and a connection legend.
/// </summary>
public class PresenceGraphRenderer
{
    private static readonly Dictionary<string, SKColor> ConnectionColors = new()
    {
        ["Bluetooth"] = new SKColor(0, 102, 217),
        ["AccessPoint"] = new SKColor(13, 133, 64),
        ["P2PWifi"] = new SKColor(199, 26, 56),
        ["WebSocket"] = new SKColor(217, 122, 0),
        ["AWDL"] = new SKColor(136, 68, 221),
        ["Cloud"] = new SKColor(115, 38, 184),
    };

    private static readonly Dictionary<string, float[]> DashPatterns = new()
    {
        ["Bluetooth"] = [3f, 3f],
        ["AccessPoint"] = [16f, 4f],
        ["P2PWifi"] = [8f, 4f],
        ["WebSocket"] = [10f, 3f, 3f, 3f],
        ["AWDL"] = [8f, 4f],
        ["Cloud"] = [8f, 4f],
    };

    /// <summary>
    /// All connection types shown in the legend, always displayed regardless of active edges.
    /// Matches SwiftUI's static connectionLegend in PresenceViewerSK.swift.
    /// </summary>
    private static readonly (string Type, string Label)[] LegendEntries =
    [
        ("Bluetooth", "Bluetooth"),
        ("AccessPoint", "LAN"),
        ("P2PWifi", "P2P Wi-Fi"),
        ("WebSocket", "WebSocket"),
        ("Cloud", "Cloud"),
    ];

    private static readonly SKColor LocalNodeColor = new(66, 133, 244);
    private static readonly SKColor RemoteNodeColor = new(76, 175, 80);
    private static readonly SKColor CloudNodeColor = new(156, 39, 176);
    private static readonly SKColor DefaultEdgeColor = new(128, 128, 140);

    /// <summary>
    /// Bottom padding in pixels to clear the floating DetailBottomBar overlay.
    /// Matches SwiftUI's .padding(.bottom, 72).
    /// </summary>
    private const float BottomPadding = 72f;

    public static SKColor GetConnectionColor(string connectionType) =>
        ConnectionColors.GetValueOrDefault(NormalizeConnectionType(connectionType), DefaultEdgeColor);

    /// <summary>
    /// Normalizes connection type strings from the SDK to canonical names used in color/dash maps.
    /// The Ditto SDK may report types with varying casing (e.g. "WiFi", "P2PWiFi", "Awdl").
    /// </summary>
    public static string NormalizeConnectionType(string type) => type switch
    {
        "WiFi" or "Wifi" or "wifi" or "accessPoint" => "AccessPoint",
        "P2PWiFi" or "p2pwifi" or "P2Pwifi" or "p2pWifi" => "P2PWifi",
        "Awdl" or "awdl" => "AWDL",
        "bluetooth" => "Bluetooth",
        "websocket" or "Websocket" => "WebSocket",
        _ => type
    };

    public void Render(
        SKCanvas canvas, float width, float height,
        PresenceGraphSnapshot snapshot,
        Dictionary<string, NodePosition> positions,
        float zoom, float panX, float panY)
    {
        canvas.Clear(SKColors.Transparent);
        if (snapshot.Nodes.Count == 0) return;

        canvas.Save();
        canvas.Translate(width / 2 + panX, height / 2 + panY);
        canvas.Scale(zoom);

        DrawEdges(canvas, snapshot, positions);
        DrawNodes(canvas, snapshot, positions);

        canvas.Restore();

        DrawLegend(canvas, width, height, snapshot);
    }

    private void DrawEdges(SKCanvas canvas, PresenceGraphSnapshot snapshot, Dictionary<string, NodePosition> positions)
    {
        // Group edges by peer pair (without connection type) so we can offset
        // multiple connection types between the same two peers.
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

                // Calculate perpendicular offset for this connection within the pair
                float lineOffset = 0f;
                if (count == 2)
                    lineOffset = i == 0 ? baseOffset : -baseOffset;
                else if (count > 2)
                    lineOffset = -baseOffset + (2 * baseOffset * i / (count - 1));

                var dx = (float)(pos2.X - pos1.X);
                var dy = (float)(pos2.Y - pos1.Y);
                var len = MathF.Sqrt(dx * dx + dy * dy);
                if (len < 0.001f) continue;

                // Perpendicular direction for offset
                var perpX = -dy / len * lineOffset;
                var perpY = dx / len * lineOffset;

                // Offset start and end points so lines are visually separated
                var fromX = (float)pos1.X + perpX;
                var fromY = (float)pos1.Y + perpY;
                var toX = (float)pos2.X + perpX;
                var toY = (float)pos2.Y + perpY;

                // Midpoint with optional outward curve for non-local edges
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

                // Cloud edges (to/from synthetic "ditto-cloud-node") use Cloud color/dash,
                // matching SwiftUI's ConnectionLine isCloudConnection override.
                var isCloudEdge = edge.PeerKey1 == "ditto-cloud-node" || edge.PeerKey2 == "ditto-cloud-node";
                var colorKey = isCloudEdge ? "Cloud" : NormalizeConnectionType(edge.ConnectionType);
                var color = ConnectionColors.GetValueOrDefault(colorKey, DefaultEdgeColor);
                var dashes = DashPatterns.GetValueOrDefault(colorKey);

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

    private void DrawNodes(SKCanvas canvas, PresenceGraphSnapshot snapshot, Dictionary<string, NodePosition> positions)
    {
        using var nodeFont = new SKFont(SKTypeface.Default, 11f);
        using var textPaint = new SKPaint { Color = SKColors.White, IsAntialias = true };

        foreach (var node in snapshot.Nodes)
        {
            if (!positions.TryGetValue(node.PeerKey, out var pos)) continue;

            var fillColor = node.IsLocal ? LocalNodeColor : node.IsCloudNode ? CloudNodeColor : RemoteNodeColor;
            var label = node.IsLocal ? "Me" : TruncateLabel(node.DeviceName, 16);
            var textWidth = nodeFont.MeasureText(label);
            var pillWidth = textWidth + 24f;
            var pillHeight = 28f;
            var cornerRadius = pillHeight / 2;

            using var fillPaint = new SKPaint
            {
                Color = fillColor,
                IsAntialias = true,
                Style = SKPaintStyle.Fill
            };

            var rect = new SKRect(
                (float)pos.X - pillWidth / 2, (float)pos.Y - pillHeight / 2,
                (float)pos.X + pillWidth / 2, (float)pos.Y + pillHeight / 2);
            canvas.DrawRoundRect(rect, cornerRadius, cornerRadius, fillPaint);
            canvas.DrawText(label, (float)pos.X, (float)pos.Y + 4f, SKTextAlign.Center, nodeFont, textPaint);
        }
    }

    /// <summary>
    /// Draws a static legend showing all connection types, matching SwiftUI's
    /// always-visible connectionLegend in PresenceViewerSK.swift.
    /// </summary>
    private static void DrawLegend(SKCanvas canvas, float width, float height, PresenceGraphSnapshot snapshot)
    {
        var entryCount = LegendEntries.Length;
        var headerHeight = 20f;
        var legendX = 16f;
        var legendY = height - BottomPadding - headerHeight - entryCount * 24f;

        using var bgPaint = new SKPaint { Color = new SKColor(0, 0, 0, 180), IsAntialias = true, Style = SKPaintStyle.Fill };
        var bgRect = new SKRect(legendX - 8, legendY - 8, legendX + 180, height - BottomPadding + 8);
        canvas.DrawRoundRect(bgRect, 8, 8, bgPaint);

        using var legendFont = new SKFont(SKTypeface.Default, 11f);
        using var headerFont = new SKFont(SKTypeface.Default, 10f);
        using var textPaint = new SKPaint { Color = SKColors.White, IsAntialias = true };
        using var headerPaint = new SKPaint { Color = new SKColor(255, 255, 255, 180), IsAntialias = true };

        // Header: "Connection Types"
        canvas.DrawText("Connection Types", legendX, legendY + 10, SKTextAlign.Left, headerFont, headerPaint);

        var y = legendY + headerHeight;
        foreach (var (type, label) in LegendEntries)
        {
            var color = ConnectionColors.GetValueOrDefault(type, DefaultEdgeColor);
            using var linePaint = new SKPaint
            {
                Color = color, StrokeWidth = 3f, IsAntialias = true, Style = SKPaintStyle.Stroke,
                PathEffect = DashPatterns.TryGetValue(type, out var dp) ? SKPathEffect.CreateDash(dp, 0) : null
            };
            canvas.DrawLine(legendX, y + 6, legendX + 30, y + 6, linePaint);
            canvas.DrawText(label, legendX + 40, y + 11, SKTextAlign.Left, legendFont, textPaint);
            y += 24;
        }
    }

    private static string TruncateLabel(string text, int maxLength)
    {
        if (text.Length <= maxLength) return text;
        return text[..(maxLength - 1)] + "\u2026";
    }
}
