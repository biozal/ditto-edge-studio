namespace EdgeStudio.Shared.Data.Repositories
{
    /// <summary>
    /// SQLite-backed repository for favorite queries.
    /// Inherits all behavior from SqliteHistoryRepository, using the query_favorites table.
    /// </summary>
    public sealed class SqliteFavoritesRepository
        : SqliteHistoryRepository, IFavoritesRepository
    {
        protected override string TableName => "query_favorites";

        public SqliteFavoritesRepository(ILocalDatabaseService localDatabaseService)
            : base(localDatabaseService) { }
    }
}
