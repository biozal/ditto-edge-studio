// EdgeStudio/Controls/PresenceGraphRenderer.cs
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;
using SkiaSharp;
using System;
using System.Collections.Generic;

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
        ["P2PWiFi"] = new SKColor(199, 26, 56),
        ["WebSocket"] = new SKColor(217, 122, 0),
        ["AWDL"] = new SKColor(136, 68, 221),
        ["Awdl"] = new SKColor(136, 68, 221),
    };

    private static readonly Dictionary<string, float[]> DashPatterns = new()
    {
        ["Bluetooth"] = [3f, 3f],
        ["AccessPoint"] = [16f, 4f],
        ["P2PWifi"] = [8f, 4f],
        ["P2PWiFi"] = [8f, 4f],
        ["WebSocket"] = [10f, 3f, 3f, 3f],
        ["AWDL"] = [8f, 4f],
        ["Awdl"] = [8f, 4f],
    };

    private static readonly SKColor LocalNodeColor = new(66, 133, 244);
    private static readonly SKColor RemoteNodeColor = new(76, 175, 80);
    private static readonly SKColor CloudNodeColor = new(156, 39, 176);
    private static readonly SKColor DefaultEdgeColor = new(128, 128, 140);

    public static SKColor GetConnectionColor(string connectionType) =>
        ConnectionColors.GetValueOrDefault(connectionType, DefaultEdgeColor);

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
        foreach (var edge in snapshot.DeduplicatedEdges)
        {
            if (!positions.TryGetValue(edge.PeerKey1, out var pos1) ||
                !positions.TryGetValue(edge.PeerKey2, out var pos2))
                continue;

            var color = GetConnectionColor(edge.ConnectionType);
            var dashes = DashPatterns.GetValueOrDefault(edge.ConnectionType);

            using var paint = new SKPaint
            {
                Color = color,
                StrokeWidth = 2f,
                IsAntialias = true,
                Style = SKPaintStyle.Stroke,
                PathEffect = dashes != null ? SKPathEffect.CreateDash(dashes, 0) : null
            };

            var midX = (float)(pos1.X + pos2.X) / 2;
            var midY = (float)(pos1.Y + pos2.Y) / 2;

            var isLocalEdge = edge.PeerKey1 == snapshot.LocalPeerKey || edge.PeerKey2 == snapshot.LocalPeerKey;
            var offset = isLocalEdge ? 0f : 20f;

            var dx = (float)(pos2.X - pos1.X);
            var dy = (float)(pos2.Y - pos1.Y);
            var len = MathF.Sqrt(dx * dx + dy * dy);
            if (len < 0.001f) continue;

            var perpX = -dy / len * offset;
            var perpY = dx / len * offset;

            using var path = new SKPath();
            path.MoveTo((float)pos1.X, (float)pos1.Y);
            path.QuadTo(midX + perpX, midY + perpY, (float)pos2.X, (float)pos2.Y);
            canvas.DrawPath(path, paint);
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

    private void DrawLegend(SKCanvas canvas, float width, float height, PresenceGraphSnapshot snapshot)
    {
        var activeTypes = new HashSet<string>();
        foreach (var edge in snapshot.DeduplicatedEdges)
            activeTypes.Add(NormalizeConnectionType(edge.ConnectionType));

        if (activeTypes.Count == 0) return;

        var legendX = 16f;
        var legendY = height - 16f - activeTypes.Count * 24f;

        using var bgPaint = new SKPaint { Color = new SKColor(0, 0, 0, 180), IsAntialias = true, Style = SKPaintStyle.Fill };
        var bgRect = new SKRect(legendX - 8, legendY - 8, legendX + 180, height - 8);
        canvas.DrawRoundRect(bgRect, 8, 8, bgPaint);

        using var legendFont = new SKFont(SKTypeface.Default, 11f);
        using var textPaint = new SKPaint { Color = SKColors.White, IsAntialias = true };

        var y = legendY;
        foreach (var type in activeTypes)
        {
            var color = GetConnectionColor(type);
            using var linePaint = new SKPaint
            {
                Color = color, StrokeWidth = 3f, IsAntialias = true, Style = SKPaintStyle.Stroke,
                PathEffect = DashPatterns.TryGetValue(type, out var dp) ? SKPathEffect.CreateDash(dp, 0) : null
            };
            canvas.DrawLine(legendX, y + 6, legendX + 30, y + 6, linePaint);
            canvas.DrawText(GetDisplayName(type), legendX + 40, y + 11, SKTextAlign.Left, legendFont, textPaint);
            y += 24;
        }
    }

    private static string NormalizeConnectionType(string type) => type switch
    {
        "P2PWiFi" => "P2PWifi",
        "Awdl" or "awdl" => "AWDL",
        _ => type
    };

    private static string GetDisplayName(string type) => type switch
    {
        "Bluetooth" => "Bluetooth",
        "AccessPoint" => "LAN / Wi-Fi",
        "P2PWifi" or "P2PWiFi" => "P2P Wi-Fi",
        "WebSocket" => "WebSocket",
        "AWDL" or "Awdl" => "AWDL",
        _ => type
    };

    private static string TruncateLabel(string text, int maxLength)
    {
        if (text.Length <= maxLength) return text;
        return text[..(maxLength - 1)] + "\u2026";
    }
}
