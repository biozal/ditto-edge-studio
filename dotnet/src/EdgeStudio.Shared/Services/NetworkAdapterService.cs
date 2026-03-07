using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using EdgeStudio.Shared.Models;

namespace EdgeStudio.Shared.Services;

/// <summary>
/// Cross-platform network adapter enumeration using System.Net.NetworkInformation.
/// SSID/BSSID/RSSI are not available via BCL and are deferred to future platform-specific extensions.
/// </summary>
public class NetworkAdapterService : INetworkAdapterService
{
    public IReadOnlyList<NetworkAdapterInfo> GetAdapters()
    {
        try
        {
            var interfaces = NetworkInterface.GetAllNetworkInterfaces();
            var adapters = new List<NetworkAdapterInfo>();

            foreach (var ni in interfaces)
            {
                // Skip loopback, tunnel, PPP — not useful to the user
                if (ni.NetworkInterfaceType is NetworkInterfaceType.Loopback
                                            or NetworkInterfaceType.Tunnel
                                            or NetworkInterfaceType.Ppp)
                    continue;

                // Skip inactive adapters
                if (ni.OperationalStatus != OperationalStatus.Up)
                    continue;

                // Skip macOS utun virtual tunnel interfaces (VPN, Back to My Mac, etc.)
                if (ni.Name.StartsWith("utun", StringComparison.OrdinalIgnoreCase))
                    continue;

                var kind = ClassifyKind(ni.NetworkInterfaceType);
                var isActive = true;

                IPInterfaceProperties? ipProps = null;
                var ipv4 = new List<string>();
                var ipv6 = new List<string>();
                string? gateway = null;

                try
                {
                    ipProps = ni.GetIPProperties();

                    foreach (var unicast in ipProps.UnicastAddresses)
                    {
                        if (unicast.Address.AddressFamily == AddressFamily.InterNetwork)
                            ipv4.Add(unicast.Address.ToString());
                        else if (unicast.Address.AddressFamily == AddressFamily.InterNetworkV6)
                            ipv6.Add(unicast.Address.ToString());
                    }

                    gateway = ipProps.GatewayAddresses
                        .FirstOrDefault(g => g.Address.AddressFamily == AddressFamily.InterNetwork)
                        ?.Address.ToString();
                }
                catch
                {
                    // IP properties may throw on some interfaces — skip gracefully
                }

                long? speed = ni.Speed > 0 ? ni.Speed : null;

                string? mac = null;
                try
                {
                    var raw = ni.GetPhysicalAddress().ToString(); // "AABBCCDDEEFF"
                    if (raw.Length == 12)
                        mac = string.Join(":", Enumerable.Range(0, 6).Select(i => raw.Substring(i * 2, 2)));
                    else if (!string.IsNullOrEmpty(raw))
                        mac = raw;
                }
                catch
                {
                    // Physical address unavailable on some virtual interfaces
                }

                adapters.Add(new NetworkAdapterInfo
                {
                    Id = ni.Id,
                    Name = ni.Name,
                    Description = ni.Description == ni.Name ? null : ni.Description,
                    Kind = kind,
                    IsActive = isActive,
                    MacAddress = mac,
                    IPv4Addresses = ipv4,
                    IPv6Addresses = ipv6,
                    GatewayAddress = gateway,
                    LinkSpeedBps = speed
                });
            }

            // Sort: Wi-Fi first, Ethernet second, Other last; stable within each group
            return adapters
                .OrderBy(a => a.Kind switch
                {
                    NetworkAdapterKind.WiFi => 0,
                    NetworkAdapterKind.Ethernet => 1,
                    _ => 2
                })
                .ToList();
        }
        catch
        {
            return Array.Empty<NetworkAdapterInfo>();
        }
    }

    private static NetworkAdapterKind ClassifyKind(NetworkInterfaceType type) => type switch
    {
        NetworkInterfaceType.Wireless80211 => NetworkAdapterKind.WiFi,
        NetworkInterfaceType.Ethernet
            or NetworkInterfaceType.GigabitEthernet
            or NetworkInterfaceType.FastEthernetT
            or NetworkInterfaceType.FastEthernetFx => NetworkAdapterKind.Ethernet,
        _ => NetworkAdapterKind.Other
    };
}
