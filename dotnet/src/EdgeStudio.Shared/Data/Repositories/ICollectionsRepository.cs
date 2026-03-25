using EdgeStudio.Shared.Models;
using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;

namespace EdgeStudio.Shared.Data.Repositories
{
    /// <summary>
    /// Repository for querying collections in the Ditto database.
    /// </summary>
    public interface ICollectionsRepository : ICloseDatabase, IDisposable
    {
        /// <summary>
        /// Registers an observer to watch for changes to collections.
        /// </summary>
        /// <param name="collections">Observable collection to populate with collection info.</param>
        /// <param name="errorMessage">Callback for error messages.</param>
        void RegisterObserver(ObservableCollection<CollectionInfo> collections, Action<string> errorMessage);

        /// <summary>
        /// Loads all collections from the Ditto database.
        /// </summary>
        /// <returns>Task that completes when collections are loaded.</returns>
        Task LoadCollectionsAsync();
    }
}
