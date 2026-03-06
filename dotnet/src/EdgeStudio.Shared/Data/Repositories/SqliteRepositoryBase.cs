using System.Threading.Tasks;

namespace EdgeStudio.Shared.Data.Repositories
{
    /// <summary>
    /// Base class for all SQLite-backed repositories. Provides access to the local database service
    /// and implements the ICloseDatabase interface (no-op for SQLite since there are no live observers).
    /// </summary>
    public abstract class SqliteRepositoryBase : ICloseDatabase
    {
        protected readonly ILocalDatabaseService _db;

        protected SqliteRepositoryBase(ILocalDatabaseService localDatabaseService)
        {
            _db = localDatabaseService;
        }

        public virtual void CloseSelectedDatabase()
        {
            // SQLite repositories have no live observers to cancel.
            // Nothing to do here - kept for interface compatibility.
        }

        public virtual Task CloseDatabaseAsync()
        {
            // SQLite repositories have no live observers to cancel.
            return Task.CompletedTask;
        }
    }
}
