using System;
using System.Collections.Generic;
using Avalonia;
using Avalonia.Media;
using CommunityToolkit.Mvvm.ComponentModel;

namespace EdgeStudio.Shared.Models;

/// <summary>
/// Observable wrapper around immutable PeerCardInfo for efficient UI updates.
/// Enables in-place property updates without destroying UI elements.
/// KEY PERFORMANCE OPTIMIZATION: Updates properties instead of replacing entire objects.
/// </summary>
public partial class ObservablePeerCardInfo : ObservableObject
{
    private PeerCardInfo _data;

    public ObservablePeerCardInfo(PeerCardInfo data)
    {
        _data = data;

        // Initialize observable properties from immutable data
        _cardType = data.CardType;
        _displayName = data.DisplayName;
        _deviceName = data.DeviceName;
        _sdkLanguage = data.SdkLanguage;
        _sdkPlatform = data.SdkPlatform;
        _sdkVersion = data.SdkVersion;
        _operatingSystem = data.OperatingSystem;
        _osIconKind = data.OsIconKind;
        _dittoAddress = data.DittoAddress;
        _activeConnections = data.ActiveConnections;
        _dittoSdkVersion = data.DittoSdkVersion;
        _identityMetadata = data.IdentityMetadata;
        _peerMetadata = data.PeerMetadata;
        _isConnected = data.IsConnected;
        _connectionStatus = data.ConnectionStatus;
        _commitId = data.CommitId;
        _lastUpdated = data.LastUpdated;
        _lastUpdatedFormatted = data.LastUpdatedFormatted;
        _syncSessionStatus = data.SyncSessionStatus;
        _isDittoServer = data.IsDittoServer;
    }

    // Immutable ID for tracking
    public string Id => _data.Id;

    // Observable properties that update in-place
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLocalPeer))]
    [NotifyPropertyChangedFor(nameof(IsRemoteOrServer))]
    private PeerCardType _cardType;

    [ObservableProperty]
    private string _displayName = string.Empty;

    [ObservableProperty]
    private string? _deviceName;

    [ObservableProperty]
    private string? _sdkLanguage;

    [ObservableProperty]
    private string? _sdkPlatform;

    [ObservableProperty]
    private string? _sdkVersion;

    [ObservableProperty]
    private string? _operatingSystem;

    [ObservableProperty]
    private string _osIconKind = "DevicesOther";

    [ObservableProperty]
    private string? _dittoAddress;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(GradientBrush))]
    [NotifyPropertyChangedFor(nameof(ActiveConnectionsCountText))]
    private List<PeerConnectionInfo>? _activeConnections;

    [ObservableProperty]
    private string? _dittoSdkVersion;

    [ObservableProperty]
    private string? _identityMetadata;

    [ObservableProperty]
    private string? _peerMetadata;

    [ObservableProperty]
    private bool _isConnected;

    [ObservableProperty]
    private string _connectionStatus = "Not Connected";

    [ObservableProperty]
    private long? _commitId;

    [ObservableProperty]
    private DateTime? _lastUpdated;

    [ObservableProperty]
    private string _lastUpdatedFormatted = "Never";

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(StatusDotBrush))]
    private string? _syncSessionStatus;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(GradientBrush))]
    private bool _isDittoServer;

    // === Computed Properties (not stored, derived on demand) ===

    /// <summary>True when this is the local peer card.</summary>
    public bool IsLocalPeer => CardType == PeerCardType.Local;

    /// <summary>True when this is a remote peer or server card (non-local).</summary>
    public bool IsRemoteOrServer => CardType != PeerCardType.Local;

    /// <summary>
    /// Gradient brush for remote/server cards, computed from the current connection type priority.
    /// Reconstructed whenever IsDittoServer or ActiveConnections changes.
    /// </summary>
    public IBrush GradientBrush
    {
        get
        {
            var (start, end) = _data.GradientHex;
            return new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(1, 1, RelativeUnit.Relative),
                GradientStops = new GradientStops
                {
                    new GradientStop { Color = Color.Parse(start), Offset = 0 },
                    new GradientStop { Color = Color.Parse(end), Offset = 1 }
                }
            };
        }
    }

    /// <summary>Brush for the status dot, keyed by SyncSessionStatus value.</summary>
    public IBrush StatusDotBrush => SyncSessionStatus switch
    {
        "Connected" => new SolidColorBrush(Color.Parse("#22C55E")),
        "Connecting" => new SolidColorBrush(Color.Parse("#F97316")),
        "Disconnected" => new SolidColorBrush(Color.Parse("#EF4444")),
        _ => new SolidColorBrush(Color.Parse("#6B7280"))
    };

    /// <summary>Formatted header for the active connections list.</summary>
    public string ActiveConnectionsCountText => $"Active Connections ({ActiveConnections?.Count ?? 0})";

    /// <summary>
    /// Updates all observable properties from new immutable data.
    /// CRITICAL: Only updates changed properties to minimize PropertyChanged events.
    /// This is the KEY optimization that prevents UI element destruction.
    /// </summary>
    public void UpdateFrom(PeerCardInfo newData)
    {
        if (_data.Id != newData.Id)
            throw new InvalidOperationException($"Cannot change peer ID from {_data.Id} to {newData.Id}");

        if (_data.CardType != newData.CardType)
            CardType = newData.CardType;

        if (_data.DisplayName != newData.DisplayName)
            DisplayName = newData.DisplayName;

        if (_data.DeviceName != newData.DeviceName)
            DeviceName = newData.DeviceName;

        if (_data.SdkLanguage != newData.SdkLanguage)
            SdkLanguage = newData.SdkLanguage;

        if (_data.SdkPlatform != newData.SdkPlatform)
            SdkPlatform = newData.SdkPlatform;

        if (_data.SdkVersion != newData.SdkVersion)
            SdkVersion = newData.SdkVersion;

        if (_data.OperatingSystem != newData.OperatingSystem)
        {
            OperatingSystem = newData.OperatingSystem;
            OsIconKind = newData.OsIconKind;
        }

        if (_data.DittoAddress != newData.DittoAddress)
            DittoAddress = newData.DittoAddress;

        if (_data.ActiveConnections != newData.ActiveConnections)
            ActiveConnections = newData.ActiveConnections;

        if (_data.DittoSdkVersion != newData.DittoSdkVersion)
            DittoSdkVersion = newData.DittoSdkVersion;

        if (_data.IdentityMetadata != newData.IdentityMetadata)
            IdentityMetadata = newData.IdentityMetadata;

        if (_data.PeerMetadata != newData.PeerMetadata)
            PeerMetadata = newData.PeerMetadata;

        if (_data.IsConnected != newData.IsConnected)
        {
            IsConnected = newData.IsConnected;
            ConnectionStatus = newData.ConnectionStatus;
        }

        if (_data.CommitId != newData.CommitId)
            CommitId = newData.CommitId;

        if (_data.LastUpdated != newData.LastUpdated)
        {
            LastUpdated = newData.LastUpdated;
            LastUpdatedFormatted = newData.LastUpdatedFormatted;
        }

        if (_data.SyncSessionStatus != newData.SyncSessionStatus)
            SyncSessionStatus = newData.SyncSessionStatus;

        if (_data.IsDittoServer != newData.IsDittoServer)
            IsDittoServer = newData.IsDittoServer;

        // Store new immutable data (must be last — GradientBrush reads from _data)
        _data = newData;
    }

    /// <summary>Gets the underlying immutable data (for serialization, export, etc.)</summary>
    public PeerCardInfo GetData() => _data;
}
