using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net.Http;
using System.Threading.Tasks;

namespace EdgeStudio.Shared.Services;

/// <summary>
/// Represents a discovered quickstart project directory.
/// </summary>
public record QuickstartProject(string Name, string DirectoryName, string Path, bool IsConfigured);

/// <summary>
/// Handles downloading the Ditto quickstart repo zip, extracting it,
/// generating .env files, generating edge-server YAML config, and discovering quickstart projects.
/// </summary>
public class QuickstartDownloadService
{
    // MARK: - Constants

    public const string ZipUrl = "https://github.com/getditto/quickstart/archive/refs/heads/main.zip";
    public const string ExtractedFolderName = "quickstart-main";

    public static readonly Dictionary<string, string> ProjectDisplayNames = new()
    {
        { "android-java", "Android Java" },
        { "android-kotlin", "Android Kotlin" },
        { "cpp-tui", "C++ TUI" },
        { "dotnet-maui", ".NET MAUI" },
        { "dotnet-tui", ".NET TUI" },
        { "dotnet-winforms", ".NET WinForms" },
        { "edge-server", "Edge Server" },
        { "flutter_app", "Flutter" },
        { "go-tui", "Go TUI" },
        { "java-server", "Java Server" },
        { "javascript-tui", "JavaScript TUI" },
        { "javascript-web", "JavaScript Web" },
        { "kotlin-multiplatform", "Kotlin Multiplatform" },
        { "react-native", "React Native" },
        { "react-native-expo", "React Native Expo" },
        { "rust-tui", "Rust TUI" },
        { "swift", "Swift" }
    };

    // MARK: - Download & Extract

    /// <summary>
    /// Downloads the quickstart zip from GitHub, extracts it to the given destination directory,
    /// and returns the path to the extracted quickstart-main folder.
    /// </summary>
    public async Task<string> DownloadAndExtractAsync(string destinationDirectory, IProgress<string>? progress = null)
    {
        progress?.Report("Starting download...");

        var tempZipPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"quickstart-{Guid.NewGuid()}.zip");
        var tempExtractDir = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"quickstart-extract-{Guid.NewGuid()}");

        try
        {
            // Download zip to temp file
            progress?.Report("Downloading quickstart zip...");
            using var httpClient = new HttpClient();
            var zipBytes = await httpClient.GetByteArrayAsync(ZipUrl);
            await File.WriteAllBytesAsync(tempZipPath, zipBytes);

            progress?.Report("Extracting archive...");

            // Extract to temp directory
            Directory.CreateDirectory(tempExtractDir);
            ZipFile.ExtractToDirectory(tempZipPath, tempExtractDir, overwriteFiles: true);

            // Copy the inner quickstart-main folder to the destination
            var extractedSourcePath = System.IO.Path.Combine(tempExtractDir, ExtractedFolderName);
            var destinationPath = System.IO.Path.Combine(destinationDirectory, ExtractedFolderName);

            if (Directory.Exists(destinationPath))
            {
                Directory.Delete(destinationPath, recursive: true);
            }

            CopyDirectory(extractedSourcePath, destinationPath);

            progress?.Report("Extraction complete.");
            return destinationPath;
        }
        finally
        {
            // Clean up temp files
            if (File.Exists(tempZipPath))
            {
                try { File.Delete(tempZipPath); } catch { /* best effort */ }
            }

            if (Directory.Exists(tempExtractDir))
            {
                try { Directory.Delete(tempExtractDir, recursive: true); } catch { /* best effort */ }
            }
        }
    }

    // MARK: - Configure .env Files

    /// <summary>
    /// Generates .env content and writes it to three locations:
    /// repo root, flutter_app/, and go-tui/.
    /// Skips non-existent subdirectories gracefully.
    /// </summary>
    public void ConfigureEnvFiles(
        string quickstartDir,
        string databaseId,
        string authToken,
        string authUrl,
        string websocketUrl)
    {
        var envContent =
            $"# Auto-configured by Edge Studio\n" +
            $"DITTO_APP_ID=\"{databaseId}\"\n" +
            $"DITTO_PLAYGROUND_TOKEN=\"{authToken}\"\n" +
            $"DITTO_AUTH_URL=\"{authUrl}\"\n" +
            $"DITTO_WEBSOCKET_URL=\"{websocketUrl}\"";

        var envLocations = new[]
        {
            System.IO.Path.Combine(quickstartDir, ".env"),
            System.IO.Path.Combine(quickstartDir, "flutter_app", ".env"),
            System.IO.Path.Combine(quickstartDir, "go-tui", ".env")
        };

        foreach (var envPath in envLocations)
        {
            var directory = System.IO.Path.GetDirectoryName(envPath);
            if (directory != null && Directory.Exists(directory))
            {
                File.WriteAllText(envPath, envContent);
            }
        }
    }

    // MARK: - Configure Edge Server YAML

    /// <summary>
    /// Generates quickstart_config.yaml in the edge-server/ subdirectory.
    /// </summary>
    public void ConfigureEdgeServerYaml(
        string quickstartDir,
        string databaseId,
        string authToken,
        string authUrl)
    {
        var yamlContent =
            $"resources:\n" +
            $"  my_ditto_db:\n" +
            $"    resource_type: DittoDatabase\n" +
            $"    db_id: \"{databaseId}\"\n" +
            $"    device_name: \"edge-studio-quickstart\"\n" +
            $"    subscriptions:\n" +
            $"      - \"SELECT * FROM tasks\"\n" +
            $"    auth:\n" +
            $"      server:\n" +
            $"        access_token: \"{authToken}\"\n" +
            $"        auth_url: \"{authUrl}\"\n" +
            $"        provider: \"__playgroundProvider\"\n" +
            $"  my_http_server:\n" +
            $"    resource_type: HttpServer\n" +
            $"    listen_addr: \"0.0.0.0:8080\"\n" +
            $"    databases:\n" +
            $"      my_db:\n" +
            $"        db_id: \"{databaseId}\"\n" +
            $"        base_path: my_server\n" +
            $"        http_api: true";

        var edgeServerDir = System.IO.Path.Combine(quickstartDir, "edge-server");
        if (!Directory.Exists(edgeServerDir))
        {
            return;
        }

        var yamlPath = System.IO.Path.Combine(edgeServerDir, "quickstart_config.yaml");
        File.WriteAllText(yamlPath, yamlContent);
    }

    // MARK: - Discover Projects

    /// <summary>
    /// Scans the quickstart directory for known project folders.
    /// Returns a list sorted by directory name.
    /// </summary>
    public List<QuickstartProject> DiscoverProjects(string quickstartDir, bool isConfigured)
    {
        var discovered = new List<QuickstartProject>();

        foreach (var (dirName, displayName) in ProjectDisplayNames)
        {
            var projectPath = System.IO.Path.Combine(quickstartDir, dirName);
            if (Directory.Exists(projectPath))
            {
                discovered.Add(new QuickstartProject(
                    Name: displayName,
                    DirectoryName: dirName,
                    Path: projectPath,
                    IsConfigured: isConfigured));
            }
        }

        return discovered.OrderBy(p => p.DirectoryName).ToList();
    }

    // MARK: - Existing Folder Check

    /// <summary>
    /// Returns the path to the quickstart-main folder if it exists inside the given directory,
    /// or null if it does not exist.
    /// </summary>
    public string? ExistingQuickstartFolder(string directory)
    {
        var folderPath = System.IO.Path.Combine(directory, ExtractedFolderName);
        return Directory.Exists(folderPath) ? folderPath : null;
    }

    // MARK: - Remove Folder

    /// <summary>
    /// Recursively removes the directory at the given path.
    /// </summary>
    public void RemoveExistingFolder(string path)
    {
        Directory.Delete(path, recursive: true);
    }

    // MARK: - Private Helpers

    /// <summary>
    /// Recursively copies a directory and all its contents to a new location.
    /// </summary>
    private static void CopyDirectory(string sourceDir, string destDir)
    {
        Directory.CreateDirectory(destDir);

        foreach (var file in Directory.GetFiles(sourceDir))
        {
            var destFile = System.IO.Path.Combine(destDir, System.IO.Path.GetFileName(file));
            File.Copy(file, destFile, overwrite: true);
        }

        foreach (var subDir in Directory.GetDirectories(sourceDir))
        {
            var destSubDir = System.IO.Path.Combine(destDir, System.IO.Path.GetFileName(subDir));
            CopyDirectory(subDir, destSubDir);
        }
    }
}
