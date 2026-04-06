using System.Threading.Tasks;
using Microsoft.Data.Sqlite;

namespace EdgeStudio.Shared.Data
{
    public class SqliteSettingsRepository : ISettingsRepository
    {
        private readonly ILocalDatabaseService _db;

        public SqliteSettingsRepository(ILocalDatabaseService db)
        {
            _db = db;
        }

        public async Task InitializeAsync()
        {
            await using var connection = _db.CreateOpenConnection();
            await using var cmd = connection.CreateCommand();
            cmd.CommandText = """
                CREATE TABLE IF NOT EXISTS app_settings (
                    key TEXT PRIMARY KEY NOT NULL,
                    value TEXT NOT NULL
                )
                """;
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<string?> GetAsync(string key)
        {
            await using var connection = _db.CreateOpenConnection();
            await using var cmd = connection.CreateCommand();
            cmd.CommandText = "SELECT value FROM app_settings WHERE key = @key";
            cmd.Parameters.AddWithValue("@key", key);
            var result = await cmd.ExecuteScalarAsync();
            return result as string;
        }

        public async Task SetAsync(string key, string value)
        {
            await using var connection = _db.CreateOpenConnection();
            await using var cmd = connection.CreateCommand();
            cmd.CommandText = """
                INSERT INTO app_settings (key, value) VALUES (@key, @value)
                ON CONFLICT(key) DO UPDATE SET value = @value
                """;
            cmd.Parameters.AddWithValue("@key", key);
            cmd.Parameters.AddWithValue("@value", value);
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<bool> GetBoolAsync(string key, bool defaultValue = false)
        {
            var value = await GetAsync(key);
            return value != null ? value == "true" : defaultValue;
        }

        public async Task SetBoolAsync(string key, bool value)
        {
            await SetAsync(key, value ? "true" : "false");
        }

        public async Task<int> GetIntAsync(string key, int defaultValue = 0)
        {
            var value = await GetAsync(key);
            return value != null && int.TryParse(value, out var result) ? result : defaultValue;
        }

        public async Task SetIntAsync(string key, int value)
        {
            await SetAsync(key, value.ToString());
        }
    }
}
