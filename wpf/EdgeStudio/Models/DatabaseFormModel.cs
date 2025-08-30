using CommunityToolkit.Mvvm.ComponentModel;

namespace EdgeStudio.Models
{
    public partial class DatabaseFormModel : ObservableObject
    {
        [ObservableProperty]
        private string id = string.Empty;
        
        [ObservableProperty]
        private string name = string.Empty;
        
        [ObservableProperty]
        private string databaseId = string.Empty;
        
        [ObservableProperty]
        private string authToken = string.Empty;
        
        [ObservableProperty]
        private string authUrl = string.Empty;
        
        [ObservableProperty]
        private string httpApiUrl = string.Empty;
        
        [ObservableProperty]
        private string httpApiKey = string.Empty;
        
        [ObservableProperty]
        private string mode = "default";
        
        [ObservableProperty]
        private bool allowUntrustedCerts = false;
        
        [ObservableProperty]
        private bool isEditMode = false;

        public void Reset()
        {
            Id = string.Empty;
            Name = string.Empty;
            DatabaseId = string.Empty;
            AuthToken = string.Empty;
            AuthUrl = string.Empty;
            HttpApiUrl = string.Empty;
            HttpApiKey = string.Empty;
            Mode = "default";
            AllowUntrustedCerts = false;
            IsEditMode = false;
        }

        public void LoadFromConfig(DittoDatabaseConfig config)
        {
            Id = config.Id;
            Name = config.Name;
            DatabaseId = config.DatabaseId;
            AuthToken = config.AuthToken;
            AuthUrl = config.AuthUrl;
            HttpApiUrl = config.HttpApiUrl;
            HttpApiKey = config.HttpApiKey;
            Mode = config.Mode;
            AllowUntrustedCerts = config.AllowUntrustedCerts;
            IsEditMode = true;
        }

        public DittoDatabaseConfig ToConfig()
        {
            return new DittoDatabaseConfig(
                Id: string.IsNullOrEmpty(Id) ? Guid.NewGuid().ToString() : Id,
                Name: Name,
                DatabaseId: DatabaseId,
                AuthToken: AuthToken,
                AuthUrl: AuthUrl,
                HttpApiUrl: HttpApiUrl,
                HttpApiKey: HttpApiKey,
                Mode: Mode,
                AllowUntrustedCerts: AllowUntrustedCerts
            );
        }
    }
}