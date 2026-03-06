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
                                // Update in place - UI element persists!
                                existingWrapper.UpdateFrom(peerCard);
                            }
                            else
                            {
                                // Add new peer
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
                DeviceName = localPeer.DeviceName,
                SdkPlatform = localPeer.Os,
                SdkVersion = localPeer.DittoSDKVersion,
                SdkLanguage = DeriveSdkLanguage(localPeer.Os, localPeer.DittoSDKVersion),
                IsDittoServer = false
            };
        }

        private static string DeriveSdkLanguage(string? os, string? sdkVersion)
        {
            if (sdkVersion?.Contains("C#") == true || sdkVersion?.Contains(".NET") == true)
                return "C#";
            if (os?.Contains("iOS") == true || os?.Contains("macOS") == true)
                return "Swift";
            if (os?.Contains("Android") == true)
                return "Kotlin";
            if (os?.Contains("Windows") == true)
                return "C#";

            return "Unknown";
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
                    ActiveConnections = remotePeer.Connections
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
