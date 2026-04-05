using EdgeStudio.Shared.Models;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace EdgeStudio.Shared.Data.Repositories
{
    /// <summary>
    /// Repository interface for managing observer definitions.
    /// Observer definitions (name, query) are persisted to SQLite.
    /// Active DittoStoreObserver instances are runtime-only.
    /// </summary>
    public interface IObserverRepository : ICloseDatabase
    {
        /// <summary>
        /// Gets all observer definitions for the currently selected database.
        /// </summary>
        Task<List<DittoDatabaseObserver>> GetObserversAsync();

        /// <summary>
        /// Saves (inserts or updates) an observer definition.
        /// </summary>
        Task SaveObserverAsync(DittoDatabaseObserver observer);

        /// <summary>
        /// Deletes an observer definition and cancels its active observer if running.
        /// </summary>
        Task DeleteObserverAsync(string observerId);

        /// <summary>
        /// Registers a DittoStoreObserver for the given observer definition.
        /// Returns true if activation succeeded.
        /// </summary>
        Task<bool> ActivateObserverAsync(DittoDatabaseObserver observer,
            System.Action<DittoSDK.Store.DittoQueryResult> callback);

        /// <summary>
        /// Cancels the active DittoStoreObserver for the given observer.
        /// </summary>
        void DeactivateObserver(string observerId);

        /// <summary>
        /// Returns true if the observer with the given ID is currently active.
        /// </summary>
        bool IsObserverActive(string observerId);
    }
}
