using System.Collections.Generic;
using EdgeStudio.Shared.Models;

namespace EdgeStudio.Shared.Services;

public interface INetworkAdapterService
{
    /// <summary>
    /// Returns a snapshot of all relevant local network adapters, sorted active-first, then Wi-Fi, Ethernet, Other.
    /// </summary>
    IReadOnlyList<NetworkAdapterInfo> GetAdapters();
}
