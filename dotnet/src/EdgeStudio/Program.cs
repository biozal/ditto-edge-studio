using Avalonia;
using System;
using System.Threading.Tasks;

namespace EdgeStudio;

sealed class Program
{
    // Initialization code. Don't use any Avalonia, third-party APIs or any
    // SynchronizationContext-reliant code before AppMain is called: things aren't initialized
    // yet and stuff might break.
    [STAThread]
    public static void Main(string[] args)
    {
        // Catch unhandled exceptions on background threads and log them before the
        // CLR terminates the process. Without this, a throw from any async void or
        // fire-and-forget task produces a bare SIGABRT with no diagnostics.
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
        {
            var ex = e.ExceptionObject as Exception;
            System.Diagnostics.Debug.WriteLine($"[FATAL] Unhandled exception: {ex}");
            Console.Error.WriteLine($"[FATAL] Unhandled exception: {ex}");
        };

        // Prevent unobserved Task exceptions from silently crashing the process.
        TaskScheduler.UnobservedTaskException += (_, e) =>
        {
            System.Diagnostics.Debug.WriteLine($"[ERROR] Unobserved task exception: {e.Exception}");
            e.SetObserved();
        };

        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
    }

    // Avalonia configuration, don't remove; also used by visual designer.
    public static AppBuilder BuildAvaloniaApp()
        => AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .WithInterFont()
            .LogToTrace();
}
