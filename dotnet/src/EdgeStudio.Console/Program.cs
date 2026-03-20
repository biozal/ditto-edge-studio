using System.Diagnostics;
using Avalonia;
using Consolonia;

namespace EdgeStudio.Console
{
    class Program
    {
        // ReSharper disable once ParameterOnlyUsedForPreconditionCheck.Local Exactly why we are keeping it here
        [STAThread]
        private static void Main(string[] args)
        {
            TaskScheduler.UnobservedTaskException += (sender, eventArgs) =>
            {
                if (Debugger.IsAttached) Debugger.Break();

                ThreadPool.QueueUserWorkItem(state =>
                    throw new InvalidOperationException("An unobserved task exception occurred.", eventArgs.Exception));
            };

            BuildAvaloniaApp()
                .StartWithConsoleLifetime(args);
        }

        public static AppBuilder BuildAvaloniaApp()
        {
            return AppBuilder.Configure<App>()
                .LogToException()
                .UseConsolonia()
                .UseAutoDetectedConsole();
        }
    }
}
