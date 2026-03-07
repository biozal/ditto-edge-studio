using Avalonia.Threading;
using DittoSDK;
using EdgeStudio.Shared.Models;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;

namespace EdgeStudio.Shared.Data.Repositories
{
    public sealed class SystemRepository(IDittoManager dittoManager)
        : ISystemRepository, IDisposable
    {
        private DittoStoreObserver? _syncStatusObserver;
        private bool _disposedValue;

        // Store registration parameters for re-registration
        private ObservableCollection<ObservablePeerCardInfo>? _registeredPeerCards;
        private Action<string>? _registeredErrorCallback;

        // Connection counts
        private ConnectionsByTransport _currentConnections = ConnectionsByTransport.Empty;
        public ConnectionsByTransport CurrentConnections => _currentConnections;
        public event EventHandler<ConnectionsByTransport>? ConnectionsChanged;


        public void CloseSelectedDatabase()
        {
            // Guard against disposed Ditto instance when cancelling observer
            try
            {
                _syncStatusObserver?.Cancel();
            }
            catch (ObjectDisposedException)
            {
                // Ditto instance already disposed - this is expected during database switching
            }
            _syncStatusObserver = null;
        }

        /// <summary>
        /// Asynchronously closes database resources by cancelling observers
        /// on a background thread to prevent UI blocking.
        /// </summary>
        public async Task CloseDatabaseAsync()
        {
            // Run observer cancellation off the UI thread (may block if callback running)
            await Task.Run(() =>
            {
                try
                {
                    _syncStatusObserver?.Cancel();
                }
                catch (ObjectDisposedException)
                {
                    // Expected during database switching - Ditto already disposed
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"Error cancelling observer: {ex.Message}");
                }
            });

            _syncStatusObserver = null;
        }

        private void Dispose(bool disposing)
        {
            if (_disposedValue)
            {
                return;
            }

            if (disposing)
            {
                CloseSelectedDatabase();
            }
            _disposedValue = true;
        }
        public void Dispose()
        {
            // Do not change this code. Put cleanup code in 'Dispose(bool disposing)' method
            Dispose(disposing: true);
            GC.SuppressFinalize(this);
        }

        private static SyncStatusInfo GetDittoSyncStatusInfoFromQueryResult(string jsonString)
        {
            // Deserialize the JSON string to SyncStatusInfo
            var syncStatusInfo = System.Text.Json.JsonSerializer.Deserialize<SyncStatusInfo>(jsonString);
            return syncStatusInfo == null ? throw new DeserializeException("Failed to deserialize SyncStatusInfo from JSON.") : syncStatusInfo!;
        }

        public void RegisterPeerCardObservers(
            ObservableCollection<ObservablePeerCardInfo> peerCards,
            Action<string> errorMessage)
        {
            // Store registration parameters for re-registration
            _registeredPeerCards = peerCards;
            _registeredErrorCallback = errorMessage;

            var ditto = dittoManager.GetSelectedAppDitto();

            // Create a local peer card once and add to the END of peerCards collection
            // Local peer will always be the last item
            if (peerCards.All(p => p.CardType != PeerCardType.Local))
            {
                var localPeerInfo = CreateLocalPeerCard(ditto.Presence.Graph.LocalPeer);
                var wrapper = new ObservablePeerCardInfo(localPeerInfo);
                Dispatcher.UIThread.InvokeAsync(() => peerCards.Add(wrapper));
            }

            // Register a DQL observer for sync status, merge with presence data
            _syncStatusObserver = ditto.Store.RegisterObserver(
                "SELECT * FROM system:data_sync_info ORDER BY documents.last_update_received_time desc",
                (result) =>
                {
                    System.Diagnostics.Debug.WriteLine($"Observer fired: {result.Items.Count} items in system:data_sync_info");

                    if (result.Items.Count == 0)
                    {
                        // Clear all remote/server peers but keep local peer
                        if (Dispatcher.UIThread.CheckAccess())
                        {
                            // Already on UI thread - execute directly
                            var remotePeers = peerCards.Where(p => p.CardType != PeerCardType.Local).ToList();
                            foreach (var peer in remotePeers)
                            {
                                peerCards.Remove(peer);
                            }
                        }
                        else
                        {
                            // Not on UI thread - invoke synchronously
                            Dispatcher.UIThread.Invoke(() =>
                            {
                                var remotePeers = peerCards.Where(p => p.CardType != PeerCardType.Local).ToList();
                                foreach (var peer in remotePeers)
                                {
                                    peerCards.Remove(peer);
                                }
                            });
                        }
                        result.Dispose();
                        return;
                    }

                    // Extract all data IMMEDIATELY before dematerialization (avoid memory leaks)
                    var extractedItems = result.Items.Select(item => GetDittoSyncStatusInfoFromQueryResult(item.JsonString())).ToList();

                    // Merge sync info with presence graph data
                    var presenceGraph = ditto.Presence.Graph;

                    // Count Ditto Cloud Servers from DQL results (they may not appear in presence graph)
                    var dittoServerCount = extractedItems.Count(x => x.IsDittoServer);

                    // Publish updated connection counts derived from the presence graph
                    PublishConnectionCounts(presenceGraph, dittoServerCount);

                    var peerCardUpdates = extractedItems
                        .Select(x => MergeSyncInfoWithPresenceGraph(x, presenceGraph))
                        .ToList();

                    // Build lookup of current IDs from query results
                    var currentIds = new HashSet<string>(extractedItems.Select(x => x.Id));

                    Dispatcher.UIThread.InvokeAsync(() =>
                    {
                        // Update or add peers from query results
                        foreach (var peerCard in peerCardUpdates)
                        {
                            var existingWrapper = peerCards.FirstOrDefault(p => p.Id == peerCard.Id);
                            if (existingWrapper != null)
                            {
                                if (peerCard.IsConnected)
                                {
                                    // Update in place - UI element persists!
                                    existingWrapper.UpdateFrom(peerCard);
                                }
                                else
                                {
                                    // Peer dropped connection — remove its card
                                    peerCards.Remove(existingWrapper);
                                }
                            }
                            else if (peerCard.IsConnected)
                            {
                                // Only add cards for connected peers
                                peerCards.Add(new ObservablePeerCardInfo(peerCard));
                            }
                        }
                    });

                    try { result.Dispose(); }
                    catch (Exception e) { errorMessage($"Disposal error: {e.Message}"); }
                });
        }

        /// <summary>
        /// Cancels the peer card observers when sync is stopped.
        /// This prevents stale observer callbacks from re-adding peers after they've been cleared.
        /// Mimics the Swift version's behavior of closing observers when sync is disabled.
        /// </summary>
        public void CancelPeerCardObservers()
        {
            // Cancel the sync status observer to stop callbacks with stale data
            try
            {
                _syncStatusObserver?.Cancel();
                _syncStatusObserver = null;
            }
            catch (ObjectDisposedException)
            {
                // Ignore - already disposed
            }

            // Reset connection counts
            _currentConnections = ConnectionsByTransport.Empty;
            Dispatcher.UIThread.InvokeAsync(() => ConnectionsChanged?.Invoke(this, ConnectionsByTransport.Empty));

            // Clear all remote/server peers from the UI, keep only local peer
            if (_registeredPeerCards != null)
            {
                // Check if we're on the UI thread
                if (Dispatcher.UIThread.CheckAccess())
                {
                    // Already on UI thread - execute directly
                    var remotePeers = _registeredPeerCards
                        .Where(p => p.CardType != PeerCardType.Local)
                        .ToList();

                    System.Diagnostics.Debug.WriteLine($"CancelPeerCardObservers: Removing {remotePeers.Count} remote peers (direct)");

                    foreach (var peer in remotePeers)
                    {
                        _registeredPeerCards.Remove(peer);
                    }
                }
                else
                {
                    // Not on UI thread - invoke synchronously
                    Dispatcher.UIThread.Invoke(() =>
                    {
                        var remotePeers = _registeredPeerCards
                            .Where(p => p.CardType != PeerCardType.Local)
                            .ToList();

                        System.Diagnostics.Debug.WriteLine($"CancelPeerCardObservers: Removing {remotePeers.Count} remote peers (invoke)");

                        foreach (var peer in remotePeers)
                        {
                            _registeredPeerCards.Remove(peer);
                        }
                    });
                }
            }
            else
            {
                System.Diagnostics.Debug.WriteLine("CancelPeerCardObservers: _registeredPeerCards is null!");
            }
        }

        /// <summary>
        /// Re-registers peer card observers using previously stored registration parameters.
        /// Called when sync is restarted to resume observer callbacks.
        /// </summary>
        public void ReregisterPeerCardObservers()
        {
            if (_registeredPeerCards == null || _registeredErrorCallback == null)
            {
                throw new InvalidStateException("No registered callback for cards or errors");
            }

            RegisterPeerCardObservers(_registeredPeerCards, _registeredErrorCallback);
            System.Diagnostics.Debug.WriteLine("ReregisterPeerCardObservers: Observer registered");
        }

        private static PeerCardInfo CreateLocalPeerCard(DittoPeer localPeer)
        {
            return new PeerCardInfo
            {
                Id = localPeer.PeerKeyString,
                CardType = PeerCardType.Local,
                DeviceName = "Edge Studio",
                SdkPlatform = localPeer.Os,
                SdkVersion = localPeer.DittoSDKVersion,
                SdkLanguage = "C# / .NET",
                IsDittoServer = false
            };
        }

        private void PublishConnectionCounts(DittoPresenceGraph presenceGraph, int dittoServerCount = 0)
        {
            int accessPoint = 0, awdl = 0, bluetooth = 0, p2pWifi = 0, webSocket = 0;

            // The SDK returns one DittoConnection per directional endpoint (A→B and B→A are
            // separate objects with the same type). Deduplicate by type per peer to avoid
            // double-counting — matching the SwiftUI implementation's seenTypes pattern.
            foreach (var peer in presenceGraph.RemotePeers)
            {
                var seenTypes = new HashSet<string>();
                foreach (var conn in peer.Connections)
                {
                    var typeStr = conn.ConnectionType.ToString();
                    if (!seenTypes.Add(typeStr))
                        continue;

                    System.Diagnostics.Debug.WriteLine($"[ConnectionCount] peer={peer.PeerKeyString} connType=\"{typeStr}\" (int={conn.ConnectionType:D})");

                    switch (typeStr)
                    {
                        case "AccessPoint":  accessPoint++;  break;
                        case "AWDL":
                        case "Awdl":
                        case "awdl":         awdl++;         break;
                        case "Bluetooth":    bluetooth++;    break;
                        case "WebSocket":    webSocket++;    break;
                        case "P2PWifi":
                        case "P2PWiFi":      p2pWifi++;      break;
                        default:
                            System.Diagnostics.Debug.WriteLine($"[ConnectionCount] UNHANDLED type: \"{typeStr}\"");
                            break;
                    }
                }
            }

            var updated = new ConnectionsByTransport(accessPoint, awdl, bluetooth, dittoServerCount, p2pWifi, webSocket);
            if (updated == _currentConnections) return;

            _currentConnections = updated;
            Dispatcher.UIThread.InvokeAsync(() => ConnectionsChanged?.Invoke(this, updated));
        }

        private static PeerCardInfo MergeSyncInfoWithPresenceGraph(
            SyncStatusInfo syncInfo,
            DittoPresenceGraph presenceGraph)
        {
            // Server card
            if (syncInfo.IsDittoServer)
            {
                return new PeerCardInfo
                {
                    Id = syncInfo.Id,
                    CardType = PeerCardType.Server,
                    IsDittoServer = true,
                    CommitId = syncInfo.Documents.SyncedUpToLocalCommitId,
                    LastUpdated = syncInfo.Documents.LastUpdateReceivedTime,
                    SyncSessionStatus = syncInfo.Documents.SyncSessionStatus
                };
            }

            // Query presence graph for this peer using LINQ
            var remotePeer = presenceGraph.RemotePeers
                .FirstOrDefault(x => x.PeerKeyString == syncInfo.Id);

            // DittoPeer is a struct - check if PeerKeyString is not empty to see if we found a match
            if (!string.IsNullOrEmpty(remotePeer.PeerKeyString))
            {
                // Remote peer WITH presence data
                return new PeerCardInfo
                {
                    Id = syncInfo.Id,
                    CardType = PeerCardType.Remote,
                    DittoAddress = syncInfo.Id,
                    DeviceName = remotePeer.DeviceName,
                    OperatingSystem = remotePeer.Os,
                    DittoSdkVersion = remotePeer.DittoSDKVersion,
                    // TODO: populate IdentityMetadata and PeerMetadata when SDK exposes them on DittoPeer
                    IdentityMetadata = null,
                    PeerMetadata = null,
                    // Deduplicate by type: the SDK returns one DittoConnection per directional
                    // endpoint (A→B and B→A), both with the same type. Keep first-seen per type
                    // to match SwiftUI's extractPeerEnrichment deduplication logic.
                    ActiveConnections = remotePeer.Connections
                        .GroupBy(c => c.ConnectionType.ToString())
                        .Select(g => g.First())
                        .Select(c => new PeerConnectionInfo
                        {
                            ConnectionType = c.ConnectionType.ToString(),
                            ConnectionId = c.Id.ToString(),
                            ApproximateDistanceInMeters = c.ApproximateDistanceInMeters
                        })
                        .ToList(),
                    CommitId = syncInfo.Documents.SyncedUpToLocalCommitId,
                    LastUpdated = syncInfo.Documents.LastUpdateReceivedTime,
                    SyncSessionStatus = syncInfo.Documents.SyncSessionStatus,
                    IsDittoServer = false
                };
            }

            // Remote peer WITHOUT presence data (shouldn't happen for connected peers, but fallback)
            return new PeerCardInfo
            {
                Id = syncInfo.Id,
                CardType = PeerCardType.Remote,
                DittoAddress = syncInfo.Id,
                DeviceName = null,
                OperatingSystem = null,
                ActiveConnections = null,
                CommitId = syncInfo.Documents.SyncedUpToLocalCommitId,
                LastUpdated = syncInfo.Documents.LastUpdateReceivedTime,
                SyncSessionStatus = syncInfo.Documents.SyncSessionStatus,
                IsDittoServer = false
            };
        }

    }
}
