// EdgeStudioTests/PresenceViewerViewModelTests.cs
using EdgeStudio.Shared.Data.Repositories;
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;
using EdgeStudio.ViewModels;
using FluentAssertions;
using Moq;

namespace EdgeStudioTests;

public class PresenceViewerViewModelTests
{
    private readonly Mock<ISystemRepository> _mockSystemRepo;
    private readonly Lazy<ISystemRepository> _lazySystemRepo;

    public PresenceViewerViewModelTests()
    {
        _mockSystemRepo = new Mock<ISystemRepository>();
        _lazySystemRepo = new Lazy<ISystemRepository>(() => _mockSystemRepo.Object);
    }

    [Fact]
    public void Constructor_ShouldInitializeWithDefaults()
    {
        var vm = new PresenceViewerViewModel(_lazySystemRepo);
        vm.ShowDirectOnly.Should().BeFalse();
        vm.ZoomLevel.Should().Be(1.0f);
        vm.ZoomPercentage.Should().Be("100%");
        vm.Snapshot.Should().BeNull();
        vm.Positions.Should().BeNull();
    }

    [Fact]
    public void ZoomIn_ShouldIncreaseZoom()
    {
        var vm = new PresenceViewerViewModel(_lazySystemRepo);
        var initial = vm.ZoomLevel;
        vm.ZoomInCommand.Execute(null);
        vm.ZoomLevel.Should().BeGreaterThan(initial);
    }

    [Fact]
    public void ZoomOut_ShouldDecreaseZoom()
    {
        var vm = new PresenceViewerViewModel(_lazySystemRepo);
        var initial = vm.ZoomLevel;
        vm.ZoomOutCommand.Execute(null);
        vm.ZoomLevel.Should().BeLessThan(initial);
    }

    [Fact]
    public void ZoomLevel_ShouldNotExceedBounds()
    {
        var vm = new PresenceViewerViewModel(_lazySystemRepo);
        for (int i = 0; i < 50; i++) vm.ZoomInCommand.Execute(null);
        vm.ZoomLevel.Should().BeLessThanOrEqualTo(3.0f);
        for (int i = 0; i < 100; i++) vm.ZoomOutCommand.Execute(null);
        vm.ZoomLevel.Should().BeGreaterThanOrEqualTo(0.3f);
    }

    [Fact]
    public void HandleGraphUpdate_ShouldSetSnapshotAndPositions()
    {
        var vm = new PresenceViewerViewModel(_lazySystemRepo);
        var nodes = new List<PresenceNode>
        {
            new("local", "Me", true, false, false, "macOS"),
            new("peer1", "Phone", false, false, false, "iOS")
        };
        var edges = new List<PresenceEdge> { new("local", "peer1", "Bluetooth", "c1") };
        var snapshot = new PresenceGraphSnapshot(nodes, edges, "local");

        vm.HandleGraphUpdate(snapshot);

        vm.Snapshot.Should().NotBeNull();
        vm.Positions.Should().NotBeNull();
        vm.Positions.Should().ContainKeys("local", "peer1");
    }

    [Fact]
    public void ShowDirectOnly_ShouldFilterSnapshot()
    {
        var vm = new PresenceViewerViewModel(_lazySystemRepo);
        var nodes = new List<PresenceNode>
        {
            new("local", "Me", true, false, false, "macOS"),
            new("peer1", "Phone", false, false, false, "iOS"),
            new("peer2", "Server", false, false, false, "Linux")
        };
        var edges = new List<PresenceEdge>
        {
            new("local", "peer1", "Bluetooth", "c1"),
            new("peer1", "peer2", "WebSocket", "c2")
        };
        var fullSnapshot = new PresenceGraphSnapshot(nodes, edges, "local");

        vm.HandleGraphUpdate(fullSnapshot);
        vm.ShowDirectOnly = true;

        vm.Snapshot!.Nodes.Should().HaveCount(2);
        vm.Snapshot.Nodes.Should().NotContain(n => n.PeerKey == "peer2");
    }
}
