using System.Threading.Tasks;

namespace EdgeStudio.Shared.Data
{
    public interface ICloseDatabase
    {
        /// <summary>
        /// Asynchronously closes the selected database and releases resources.
        /// Use this method for user-initiated close operations.
        /// </summary>
        Task CloseDatabaseAsync();

        /// <summary>
        /// Synchronously closes the selected database (for Dispose pattern).
        /// </summary>
		void CloseSelectedDatabase();
    }
}
