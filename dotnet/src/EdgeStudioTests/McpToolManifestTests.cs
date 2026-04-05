using System.ComponentModel;
using System.Linq;
using System.Reflection;
using EdgeStudio.Data.McpServer;
using FluentAssertions;
using ModelContextProtocol.Server;
using Xunit;

namespace EdgeStudioTests
{
    public class McpToolManifestTests
    {
        private static readonly Assembly ToolAssembly = typeof(McpServerService).Assembly;

        [Fact]
        public void AllToolClasses_HaveMcpServerToolTypeAttribute()
        {
            var toolTypes = ToolAssembly.GetTypes()
                .Where(t => t.GetCustomAttribute<McpServerToolTypeAttribute>() != null)
                .ToList();

            toolTypes.Should().NotBeEmpty("there should be MCP tool classes in the assembly");
            toolTypes.Count.Should().Be(5, "there should be 5 tool classes");
        }

        [Fact]
        public void AllTools_HaveUniqueNames()
        {
            var toolMethods = GetAllToolMethods();
            var names = toolMethods.Select(m => m.Name).ToList();
            names.Should().OnlyHaveUniqueItems("MCP tool names must be unique");
        }

        [Fact]
        public void AllTools_HaveDescriptions()
        {
            var toolMethods = GetAllToolMethods();

            foreach (var method in toolMethods)
            {
                var desc = method.GetCustomAttribute<DescriptionAttribute>();
                desc.Should().NotBeNull($"tool {method.Name} must have a [Description] attribute");
                desc!.Description.Should().NotBeNullOrWhiteSpace($"tool {method.Name} description should not be empty");
            }
        }

        [Fact]
        public void ToolCount_MatchesExpected()
        {
            var toolMethods = GetAllToolMethods();
            toolMethods.Count.Should().Be(15, "should have 15 tools matching the SwiftUI version");
        }

        private static System.Collections.Generic.List<MethodInfo> GetAllToolMethods()
        {
            return ToolAssembly.GetTypes()
                .Where(t => t.GetCustomAttribute<McpServerToolTypeAttribute>() != null)
                .SelectMany(t => t.GetMethods(BindingFlags.Public | BindingFlags.Static))
                .Where(m => m.GetCustomAttribute<McpServerToolAttribute>() != null)
                .ToList();
        }
    }
}
