using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Shared.Services;
using System;

namespace EdgeStudio.ViewModels;

/// <summary>
/// Base class for ViewModels that require cleanup of resources.
/// Implements the standard Disposable pattern with proper messenger cleanup.
/// </summary>
public abstract class DisposableViewModelBase : ViewModelBase, IDisposable
{
    private bool _disposed;

    /// <summary>
    /// Default constructor for ViewModels that don't need toast notifications
    /// </summary>
    protected DisposableViewModelBase() : base()
    {
    }

    /// <summary>
    /// Constructor with optional toast service injection
    /// </summary>
    protected DisposableViewModelBase(IToastService? toastService) : base(toastService)
    {
    }

    /// <summary>
    /// Override to perform cleanup of managed resources.
    /// Always call base.OnDisposing() when overriding.
    /// </summary>
    protected virtual void OnDisposing()
    {
        // Unregister all messenger subscriptions to prevent memory leaks
        WeakReferenceMessenger.Default.UnregisterAll(this);
    }

    /// <summary>
    /// Disposes the ViewModel and cleans up resources
    /// </summary>
    public void Dispose()
    {
        if (_disposed)
            return;

        OnDisposing();
        _disposed = true;
        GC.SuppressFinalize(this);
    }
}
