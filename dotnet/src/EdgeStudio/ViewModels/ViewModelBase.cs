using CommunityToolkit.Mvvm.ComponentModel;
using EdgeStudio.Shared.Services;
using System;

namespace EdgeStudio.ViewModels;

/// <summary>
/// Base class for all ViewModels providing core infrastructure:
/// - Property change notification via ObservableObject
/// - Toast notification service integration
/// - Virtual lifecycle hooks for derived classes
/// </summary>
public abstract class ViewModelBase : ObservableObject
{
    private IToastService? _toastService;
    private bool _isInitialized;

    /// <summary>
    /// Optional toast service for displaying notifications.
    /// Can be set via constructor injection or property injection.
    /// </summary>
    protected IToastService? ToastService
    {
        get => _toastService;
        set => _toastService = value;
    }

    /// <summary>
    /// Default constructor for ViewModels that don't need toast notifications
    /// </summary>
    protected ViewModelBase()
    {
    }

    /// <summary>
    /// Constructor with optional toast service injection
    /// </summary>
    protected ViewModelBase(IToastService? toastService)
    {
        _toastService = toastService;
    }

    /// <summary>
    /// Called when the ViewModel is first initialized. Override for initialization logic.
    /// Guaranteed to be called only once.
    /// </summary>
    protected virtual void OnInitialize()
    {
    }

    /// <summary>
    /// Called when the ViewModel becomes active/visible. Override for activation logic.
    /// May be called multiple times during the ViewModel's lifetime.
    /// </summary>
    protected virtual void OnActivated()
    {
    }

    /// <summary>
    /// Called when the ViewModel becomes inactive/hidden. Override for deactivation logic.
    /// May be called multiple times during the ViewModel's lifetime.
    /// </summary>
    protected virtual void OnDeactivated()
    {
    }

    /// <summary>
    /// Ensures initialization happens exactly once
    /// </summary>
    public void Initialize()
    {
        if (_isInitialized)
            return;

        OnInitialize();
        _isInitialized = true;
    }

    /// <summary>
    /// Activates the ViewModel
    /// </summary>
    public void Activate()
    {
        if (!_isInitialized)
        {
            Initialize();
        }

        OnActivated();
    }

    /// <summary>
    /// Deactivates the ViewModel
    /// </summary>
    public void Deactivate()
    {
        OnDeactivated();
    }

    /// <summary>
    /// Displays an error notification using the toast service (5 second duration)
    /// </summary>
    protected void ShowError(string message, string? title = null)
    {
        _toastService?.ShowError(message, title);
    }

    /// <summary>
    /// Displays a success notification using the toast service (3 second duration)
    /// </summary>
    protected void ShowSuccess(string message, string? title = null)
    {
        _toastService?.ShowSuccess(message, title);
    }

    /// <summary>
    /// Displays a warning notification using the toast service (4 second duration)
    /// </summary>
    protected void ShowWarning(string message, string? title = null)
    {
        _toastService?.ShowWarning(message, title);
    }

    /// <summary>
    /// Displays an informational notification using the toast service (4 second duration)
    /// </summary>
    protected void ShowInfo(string message, string? title = null)
    {
        _toastService?.ShowInfo(message, title);
    }
}
