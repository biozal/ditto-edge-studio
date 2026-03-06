using EdgeStudio.Shared.Models;
using System;
using System.Collections.ObjectModel;

namespace EdgeStudio.Shared.Data.Repositories
{
    public interface ISystemRepository : ICloseDatabase
    {
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
    }
}
