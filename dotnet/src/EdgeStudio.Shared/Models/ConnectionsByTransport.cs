using System.Collections.Generic;
using Avalonia.Media;
using Material.Icons;

namespace EdgeStudio.Shared.Models;

/// <summary>
/// Per-transport connection counts derived from Ditto's presence graph.
/// </summary>
public sealed record ConnectionsByTransport(
    int AccessPoint,
    int Awdl,
    int Bluetooth,
    int DittoServer,
    int P2PWifi,
    int WebSocket)
{
    public static readonly ConnectionsByTransport Empty = new(0, 0, 0, 0, 0, 0);

    public int TotalConnections => AccessPoint + Awdl + Bluetooth + DittoServer + P2PWifi + WebSocket;
    public bool HasActiveConnections => TotalConnections > 0;

    /// <summary>
    /// Active (non-zero) transports with display metadata, in Ditto rainbow color order.
    /// </summary>
    public IReadOnlyList<TransportInfo> ActiveTransports
    {
        get
        {
            var list = new List<TransportInfo>();
            if (WebSocket > 0)
                list.Add(new("WebSocket",    WebSocket,   MaterialIconKind.Web,           Color.Parse("#E65100")));
            if (Bluetooth > 0)
                list.Add(new("Bluetooth",    Bluetooth,   MaterialIconKind.Bluetooth,     Color.Parse("#1565C0")));
            if (P2PWifi > 0)
                list.Add(new("P2P WiFi",     P2PWifi,     MaterialIconKind.Wifi,          Color.Parse("#B71C1C")));
            if (AccessPoint > 0)
                list.Add(new("Access Point", AccessPoint, MaterialIconKind.RouterWireless, Color.Parse("#2E7D32")));
            if (Awdl > 0)
                list.Add(new("AWDL",         Awdl,        MaterialIconKind.AppleAirplay,  Color.Parse("#8844DD")));
            if (DittoServer > 0)
                list.Add(new("Ditto Server", DittoServer, MaterialIconKind.Cloud,         Color.Parse("#6A1B9A")));
            return list;
        }
    }
}

/// <summary>
/// Display metadata for a single active transport.
/// </summary>
public sealed record TransportInfo(
    string Name,
    int Count,
    MaterialIconKind Icon,
    Color DotColor)
{
    public IBrush DotBrush => new SolidColorBrush(DotColor);
}
