using CommunityToolkit.Mvvm.ComponentModel;
using EdgeStudio.Shared.Services;
using System;
using System.Threading.Tasks;

namespace EdgeStudio.ViewModels;

/// <summary>
/// Base class for ViewModels that load data asynchronously.
/// Provides built-in loading state management, error handling, and async operation support.
/// </summary>
public abstract partial class LoadableViewModelBase : DisposableViewModelBase
{
    [ObservableProperty]
    private bool _isLoading;

    [ObservableProperty]
    private bool _isBusy;

    [ObservableProperty]
    private string? _busyMessage;

    /// <summary>
    /// Default constructor for ViewModels that don't need toast notifications
    /// </summary>
    protected LoadableViewModelBase() : base()
    {
    }

    /// <summary>
    /// Constructor with optional toast service injection
    /// </summary>
    protected LoadableViewModelBase(IToastService? toastService) : base(toastService)
    {
    }

    /// <summary>
    /// Executes an async operation with loading state and error handling
    /// </summary>
    /// <param name="operation">The async operation to execute</param>
    /// <param name="errorMessage">Optional custom error message prefix</param>
    /// <param name="showLoadingState">Whether to show loading state during execution</param>
    /// <param name="showSuccessToast">Whether to show a success toast after completion</param>
    /// <param name="successMessage">Optional success message to display</param>
    protected async Task ExecuteOperationAsync(
        Func<Task> operation,
        string? errorMessage = null,
        bool showLoadingState = true,
        bool showSuccessToast = false,
        string? successMessage = null)
    {
        try
        {
            if (showLoadingState)
            {
                IsLoading = true;
            }

            await operation();

            if (showSuccessToast && !string.IsNullOrEmpty(successMessage))
            {
                ShowSuccess(successMessage);
            }
        }
        catch (Exception ex)
        {
            var message = errorMessage != null
                ? $"{errorMessage}: {ex.Message}"
                : $"An error occurred: {ex.Message}";
            ShowError(message);
        }
        finally
        {
            if (showLoadingState)
            {
                IsLoading = false;
            }
        }
    }

    /// <summary>
    /// Executes an async operation with loading state and error handling, returning a result
    /// </summary>
    /// <typeparam name="T">The type of result to return</typeparam>
    /// <param name="operation">The async operation to execute</param>
    /// <param name="errorMessage">Optional custom error message prefix</param>
    /// <param name="showLoadingState">Whether to show loading state during execution</param>
    /// <returns>The result of the operation, or default(T) if an error occurred</returns>
    protected async Task<T?> ExecuteOperationAsync<T>(
        Func<Task<T>> operation,
        string? errorMessage = null,
        bool showLoadingState = true)
    {
        try
        {
            if (showLoadingState)
            {
                IsLoading = true;
            }

            return await operation();
        }
        catch (Exception ex)
        {
            var message = errorMessage != null
                ? $"{errorMessage}: {ex.Message}"
                : $"An error occurred: {ex.Message}";
            ShowError(message);
            return default;
        }
        finally
        {
            if (showLoadingState)
            {
                IsLoading = false;
            }
        }
    }

    /// <summary>
    /// Sets a busy state with an optional message (for long-running operations)
    /// </summary>
    /// <param name="isBusy">Whether the ViewModel is busy</param>
    /// <param name="message">Optional message describing what is happening</param>
    protected void SetBusy(bool isBusy, string? message = null)
    {
        IsBusy = isBusy;
        BusyMessage = message;
    }
}
