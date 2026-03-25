using System;
using System.Threading.Tasks;
using Microsoft.Data.Sqlite;

namespace EdgeStudio.Shared.Data
{
    /// <summary>
    /// Provides access to the local encrypted SQLite database that replaces the Ditto local cache.
    /// The database is encrypted at rest using a device-derived key (no user password required).
    /// </summary>
    public interface ILocalDatabaseService : IDisposable
    {
        /// <summary>
        /// Initializes the SQLite provider and creates the database schema if it does not exist.
        /// Must be called once before any other operations.
        /// </summary>
        Task InitializeAsync();

        /// <summary>
        /// Creates and returns a new open, encrypted SQLite connection.
        /// The caller is responsible for disposing the connection.
        /// </summary>
        SqliteConnection CreateOpenConnection();
    }
}
