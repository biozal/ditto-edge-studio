using System.Collections.Generic;
using System.Linq;
using Avalonia;
using Avalonia.Media;
using Material.Icons;

namespace EdgeStudio.Shared.Models;

public enum NetworkAdapterKind { WiFi, Ethernet, Other }

/// <summary>
/// Immutable snapshot of a local network interface, built from System.Net.NetworkInformation.
/// SSID, BSSID, RSSI, and link duplex are deferred to future platform-specific extensions.
/// </summary>
public record NetworkAdapterInfo
{
    public required string Id { get; init; }
    public required string Name { get; init; }
    public string? Description { get; init; }
    public required NetworkAdapterKind Kind { get; init; }
    public required bool IsActive { get; init; }
    public string? MacAddress { get; init; }
    public required IReadOnlyList<string> IPv4Addresses { get; init; }
    public required IReadOnlyList<string> IPv6Addresses { get; init; }
    public string? GatewayAddress { get; init; }

    /// <summary>Null when the OS reports -1 or 0 (e.g., Wi-Fi on macOS).</summary>
    public long? LinkSpeedBps { get; init; }

    public string LinkSpeedFormatted
    {
        get
        {
            if (LinkSpeedBps is null or <= 0) return "N/A";
            var bps = LinkSpeedBps.Value;
            if (bps >= 1_000_000_000) return $"{bps / 1_000_000_000} Gbps";
            if (bps >= 1_000_000) return $"{bps / 1_000_000} Mbps";
            if (bps >= 1_000) return $"{bps / 1_000} Kbps";
            return $"{bps} bps";
        }
    }

    public (string Start, string End) GradientHex => Kind switch
    {
        NetworkAdapterKind.WiFi => ("#0D8540", "#055224"),
        NetworkAdapterKind.Ethernet => ("#0D7380", "#054752"),
        _ => ("#595966", "#333340")
    };

    public IBrush GradientBrush
    {
        get
        {
            var (start, end) = GradientHex;
            return new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(1, 1, RelativeUnit.Relative),
                GradientStops = new GradientStops
                {
                    new GradientStop { Color = Color.Parse(start), Offset = 0 },
                    new GradientStop { Color = Color.Parse(end), Offset = 1 }
                }
            };
        }
    }

    public IBrush ActiveDotBrush => IsActive
        ? new SolidColorBrush(Color.Parse("#22C55E"))
        : new SolidColorBrush(Color.Parse("#6B7280"));

    public string ActiveLabel => IsActive ? "Active" : "Inactive";

    public string KindLabel => Kind switch
    {
        NetworkAdapterKind.WiFi => "Wi-Fi",
        NetworkAdapterKind.Ethernet => "Ethernet",
        _ => "Network"
    };

    public MaterialIconKind IconKind => Kind switch
    {
        NetworkAdapterKind.WiFi => MaterialIconKind.Wifi,
        NetworkAdapterKind.Ethernet => MaterialIconKind.Ethernet,
        _ => MaterialIconKind.NetworkInterfaceCard
    };
}
