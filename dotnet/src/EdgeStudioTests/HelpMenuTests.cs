using System;
using System.IO;
using Xunit;
using FluentAssertions;

namespace EdgeStudioTests;

public class HelpMenuTests
{
    [Fact]
    public void UserGuide_AssetFile_ExistsInHelpDirectory()
    {
        var projectDir = FindProjectDirectory();
        var helpFile = Path.Combine(projectDir, "Assets", "Help", "UserGuide.md");
        File.Exists(helpFile).Should().BeTrue(
            because: "UserGuide.md should be synced from docs/help/ by the SyncHelpDocs build target");
    }

    [Fact]
    public void UserGuide_AssetFile_HasContent()
    {
        var projectDir = FindProjectDirectory();
        var helpFile = Path.Combine(projectDir, "Assets", "Help", "UserGuide.md");

        File.Exists(helpFile).Should().BeTrue(
            because: "UserGuide.md must exist before content can be validated");

        var content = File.ReadAllText(helpFile);
        content.Should().NotBeNullOrWhiteSpace(because: "UserGuide.md should contain documentation");
        content.Should().Contain("# ", because: "UserGuide.md should contain markdown headings");
    }

    [Fact]
    public void DittoWebsiteUrl_IsValid()
    {
        const string url = "https://www.ditto.com/";
        var uri = new Uri(url);
        uri.Scheme.Should().Be("https");
        uri.Host.Should().Be("www.ditto.com");
    }

    private static string FindProjectDirectory()
    {
        var dir = AppContext.BaseDirectory;
        while (dir != null)
        {
            var candidate = Path.Combine(dir, "EdgeStudio");
            if (Directory.Exists(candidate) && Directory.Exists(Path.Combine(candidate, "Assets")))
                return candidate;

            var csproj = Path.Combine(dir, "EdgeStudio", "EdgeStudio.csproj");
            if (File.Exists(csproj))
                return Path.Combine(dir, "EdgeStudio");

            dir = Directory.GetParent(dir)?.FullName;
        }

        var testDir = Path.GetDirectoryName(typeof(HelpMenuTests).Assembly.Location)!;
        return Path.GetFullPath(Path.Combine(testDir, "..", "..", "..", "..", "EdgeStudio"));
    }
}
