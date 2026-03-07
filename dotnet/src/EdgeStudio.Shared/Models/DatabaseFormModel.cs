using System;
using System.Collections.Generic;
using CommunityToolkit.Mvvm.ComponentModel;

namespace EdgeStudio.Shared.Models
{
    public partial class DatabaseFormModel : ObservableObject
    {
        public static readonly IReadOnlyList<string> LogLevelOptions =
            ["error", "warning", "info", "debug", "verbose"];

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
        private string websocketUrl = string.Empty;

        [ObservableProperty]
        private string httpApiUrl = string.Empty;

        [ObservableProperty]
        private string httpApiKey = string.Empty;

        [ObservableProperty]
        private string mode = "server";

        [ObservableProperty]
        private bool allowUntrustedCerts = false;

        [ObservableProperty]
        private bool isEditMode = false;

        [ObservableProperty]
        private bool isBluetoothLeEnabled = true;

        [ObservableProperty]
        private bool isLanEnabled = true;

        [ObservableProperty]
        private bool isAwdlEnabled = true;

        [ObservableProperty]
        private bool isCloudSyncEnabled = true;

        [ObservableProperty]
        private bool isStrictModeEnabled = false;

        [ObservableProperty]
        private string logLevel = "info";

        [ObservableProperty]
        private string sharedKey = string.Empty;

        public bool IsOnlineMode
        {
            get => Mode == "server";
            set
            {
                if (value)
                {
                    Mode = "server";
                }
                OnPropertyChanged(nameof(IsOnlineMode));
                OnPropertyChanged(nameof(IsOfflineMode));
            }
        }

        public bool IsOfflineMode
        {
            get => Mode == "smallpeersonly";
            set
            {
                if (value)
                {
                    Mode = "smallpeersonly";
                }
                OnPropertyChanged(nameof(IsOnlineMode));
                OnPropertyChanged(nameof(IsOfflineMode));
            }
        }

        partial void OnModeChanged(string value)
        {
            OnPropertyChanged(nameof(IsOnlineMode));
            OnPropertyChanged(nameof(IsOfflineMode));
        }

        public void Reset()
        {
            Id = string.Empty;
            Name = string.Empty;
            DatabaseId = string.Empty;
            AuthToken = string.Empty;
            AuthUrl = string.Empty;
            WebsocketUrl = string.Empty;
            HttpApiUrl = string.Empty;
            HttpApiKey = string.Empty;
            Mode = "server";
            AllowUntrustedCerts = false;
            IsEditMode = false;
            IsBluetoothLeEnabled = true;
            IsLanEnabled = true;
            IsAwdlEnabled = true;
            IsCloudSyncEnabled = true;
            IsStrictModeEnabled = false;
            LogLevel = "info";
            SharedKey = string.Empty;
        }

        public void LoadFromConfig(DittoDatabaseConfig config)
        {
            Id = config.Id;
            Name = config.Name;
            DatabaseId = config.DatabaseId;
            AuthToken = config.AuthToken;
            AuthUrl = config.AuthUrl;
            WebsocketUrl = config.WebsocketUrl;
            HttpApiUrl = config.HttpApiUrl;
            HttpApiKey = config.HttpApiKey;
            Mode = config.Mode;
            AllowUntrustedCerts = config.AllowUntrustedCerts;
            IsBluetoothLeEnabled = config.IsBluetoothLeEnabled;
            IsLanEnabled = config.IsLanEnabled;
            IsAwdlEnabled = config.IsAwdlEnabled;
            IsCloudSyncEnabled = config.IsCloudSyncEnabled;
            IsStrictModeEnabled = config.IsStrictModeEnabled;
            LogLevel = config.LogLevel;
            SharedKey = config.SharedKey;
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
                AllowUntrustedCerts: AllowUntrustedCerts,
                IsBluetoothLeEnabled: IsBluetoothLeEnabled,
                IsLanEnabled: IsLanEnabled,
                IsAwdlEnabled: IsAwdlEnabled,
                IsCloudSyncEnabled: IsCloudSyncEnabled,
                WebsocketUrl: WebsocketUrl,
                IsStrictModeEnabled: IsStrictModeEnabled,
                LogLevel: LogLevel,
                SharedKey: SharedKey
            );
        }
    }
}
