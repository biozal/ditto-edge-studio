using EdgeStudio.Shared.Models;
using System;
using System.Collections.ObjectModel;

namespace EdgeStudio.Shared.Data.Repositories
{
    public interface ISystemRepository : ICloseDatabase
    {
        /// <summary>
        /// Current aggregated connection counts by transport type, derived from the presence graph.
        /// Updated every time the sync-status observer fires.
        /// </summary>
        ConnectionsByTransport CurrentConnections { get; }

        /// <summary>
        /// Raised on the UI thread whenever CurrentConnections changes.
        /// </summary>
        event EventHandler<ConnectionsByTransport>? ConnectionsChanged;

        /// <summary>
        /// Registers observers for peer information, merging DQL sync status with Presence Graph data.
        /// Local peer is added as the last item in the collection.
        /// </summary>
        /// <param name="peerCards">Collection for all peers (remote, server, and local)</param>
        /// <param name="errorMessage">Error callback</param>
        void RegisterPeerCardObservers(
            ObservableCollection<ObservablePeerCardInfo> peerCards,
            Action<string> errorMessage);

        /// <summary>
        /// Cancels the peer card observers when sync is stopped.
        /// This prevents stale observer callbacks from re-adding peers after they've been cleared.
        /// </summary>
        void CancelPeerCardObservers();

        /// <summary>
        /// Re-registers peer card observers using previously stored registration parameters.
        /// Called when sync is restarted to resume observer callbacks.
        /// </summary>
        void ReregisterPeerCardObservers();

        /// <summary>
        /// Registers an observer that provides full presence graph snapshots (all peers, all connections).
        /// Used by the Presence Viewer for mesh topology visualization.
        /// </summary>
        void RegisterPresenceGraphObserver(Action<PresenceGraphSnapshot> onUpdate, Action<string> onError);

        /// <summary>
        /// Cancels the presence graph observer.
        /// </summary>
        void CancelPresenceGraphObserver();
    }
}
