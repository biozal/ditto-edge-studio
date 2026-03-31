// EdgeStudioTests/PresenceGraphRendererTests.cs
using EdgeStudio.Controls;
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;
using FluentAssertions;
using SkiaSharp;

namespace EdgeStudioTests;

public class PresenceGraphRendererTests
{
    [Fact]
    public void Render_EmptyGraph_ShouldNotThrow()
    {
        var snapshot = new PresenceGraphSnapshot(
            new List<PresenceNode>(), new List<PresenceEdge>(), "local");
        var positions = new Dictionary<string, NodePosition>();
        var renderer = new PresenceGraphRenderer();

        using var bitmap = new SKBitmap(800, 600);
        using var canvas = new SKCanvas(bitmap);

        var act = () => renderer.Render(canvas, 800, 600, snapshot, positions, 1.0f, 0, 0);
        act.Should().NotThrow();
    }

    [Fact]
    public void Render_WithNodes_ShouldNotThrow()
    {
        var nodes = new List<PresenceNode>
        {
            new("local", "Me", true, false, false, "macOS"),
            new("peer1", "Phone", false, false, false, "iOS")
        };
        var edges = new List<PresenceEdge> { new("local", "peer1", "Bluetooth", "c1") };
        var snapshot = new PresenceGraphSnapshot(nodes, edges, "local");
        var positions = NetworkLayoutEngine.ComputeLayout(snapshot);
        var renderer = new PresenceGraphRenderer();

        using var bitmap = new SKBitmap(800, 600);
        using var canvas = new SKCanvas(bitmap);

        var act = () => renderer.Render(canvas, 800, 600, snapshot, positions, 1.0f, 0, 0);
        act.Should().NotThrow();
    }

    [Fact]
    public void GetConnectionColor_ShouldReturnExpectedColors()
    {
        PresenceGraphRenderer.GetConnectionColor("Bluetooth").Should().NotBe(SKColor.Empty);
        PresenceGraphRenderer.GetConnectionColor("WebSocket").Should().NotBe(SKColor.Empty);
        PresenceGraphRenderer.GetConnectionColor("AccessPoint").Should().NotBe(SKColor.Empty);
        PresenceGraphRenderer.GetConnectionColor("P2PWifi").Should().NotBe(SKColor.Empty);
    }
}
