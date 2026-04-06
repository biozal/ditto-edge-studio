using System.Threading.Tasks;

namespace EdgeStudio.Shared.Data
{
    public interface ISettingsRepository
    {
        Task InitializeAsync();
        Task<string?> GetAsync(string key);
        Task SetAsync(string key, string value);
        Task<bool> GetBoolAsync(string key, bool defaultValue = false);
        Task SetBoolAsync(string key, bool value);
        Task<int> GetIntAsync(string key, int defaultValue = 0);
        Task SetIntAsync(string key, int value);
    }
}
