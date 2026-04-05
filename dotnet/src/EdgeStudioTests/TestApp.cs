using Avalonia;
using Avalonia.Headless;
using Avalonia.Themes.Fluent;

namespace EdgeStudioTests;

/// <summary>
/// Minimal Avalonia application for headless unit tests.
/// Required by Avalonia.Headless.XUnit for tests that need the Avalonia render platform.
/// </summary>
public sealed class TestApp : Application
{
    public override void Initialize()
    {
        Styles.Add(new FluentTheme());
    }

    /// <summary>
    /// Called by Avalonia.Headless.XUnit to set up the headless test session.
    /// </summary>
    public static AppBuilder BuildAvaloniaApp()
        => AppBuilder.Configure<TestApp>()
            .UseHeadless(new AvaloniaHeadlessPlatformOptions { UseHeadlessDrawing = false });
}
