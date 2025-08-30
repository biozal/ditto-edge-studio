using System.IO;
using System.Reflection;

namespace EdgeStudio.Helpers
{
    public static class EnvFileReader
    {
        public static Dictionary<string, string> Read()
        {
            var envVars = new Dictionary<string, string>();
            
            // Read from embedded resource
            var assembly = Assembly.GetExecutingAssembly();
            var resourceName = "EdgeStudio..env"; // Default namespace + filename
            
            using (var stream = assembly.GetManifestResourceStream(resourceName))
            {
                if (stream == null)
                {
                    throw new InvalidOperationException($"Could not find embedded resource: {resourceName}. " +
                        $"Available resources: {string.Join(", ", assembly.GetManifestResourceNames())}");
                }
                
                using (var reader = new StreamReader(stream))
                {
                    string? line;
                    while ((line = reader.ReadLine()) != null)
                    {
                        if (string.IsNullOrWhiteSpace(line) || line.StartsWith("#"))
                            continue;
                            
                        var parts = line.Split('=', 2);
                        if (parts.Length == 2)
                        {
                            var key = parts[0].Trim();
                            var value = parts[1].Trim();
                            
                            // Remove quotes if present
                            if ((value.StartsWith("\"") && value.EndsWith("\"")) || 
                                (value.StartsWith("'") && value.EndsWith("'")))
                            {
                                value = value.Substring(1, value.Length - 2);
                            }
                            
                            envVars[key] = value;
                        }
                    }
                }
            }
            
            return envVars;
        }
        
        // Overload for backwards compatibility or testing with file path
        public static Dictionary<string, string> ReadFromFile(string filePath)
        {
            var envVars = new Dictionary<string, string>();
            
            if (!File.Exists(filePath))
            {
                throw new FileNotFoundException($"The .env file was not found at: {Path.GetFullPath(filePath)}");
            }
            
            foreach (var line in File.ReadAllLines(filePath))
            {
                if (string.IsNullOrWhiteSpace(line) || line.StartsWith("#"))
                    continue;
                    
                var parts = line.Split('=', 2);
                if (parts.Length == 2)
                {
                    var key = parts[0].Trim();
                    var value = parts[1].Trim();
                    
                    // Remove quotes if present
                    if ((value.StartsWith("\"") && value.EndsWith("\"")) || 
                        (value.StartsWith("'") && value.EndsWith("'")))
                    {
                        value = value.Substring(1, value.Length - 2);
                    }
                    
                    envVars[key] = value;
                }
            }
            
            return envVars;
        }
    }
}