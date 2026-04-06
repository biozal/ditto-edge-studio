using System;
using System.IO;
using Avalonia.Controls;
using Avalonia.Platform;
using EdgeStudio.Views.StudioView.Inspector;
using SukiUI.Controls;

namespace EdgeStudio.Views.Help;

public partial class UserGuideWindow : SukiWindow
{
    private static readonly Uri UserGuideUri = new("avares://EdgeStudio/Assets/Help/UserGuide.md");

    public UserGuideWindow()
    {
        InitializeComponent();
        LoadMarkdownContent();
    }

    private void LoadMarkdownContent()
    {
        try
        {
            using var stream = AssetLoader.Open(UserGuideUri);
            using var reader = new StreamReader(stream);
            var markdown = reader.ReadToEnd();
            MarkdownContainer.Content = SimpleMarkdownRenderer.Render(markdown);
        }
        catch (Exception)
        {
            MarkdownContainer.Content = new TextBlock
            {
                Text = "Unable to load documentation. The UserGuide.md file may be missing.",
                TextWrapping = Avalonia.Media.TextWrapping.Wrap
            };
        }
    }
}
