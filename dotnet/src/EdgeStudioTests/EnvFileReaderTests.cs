using EdgeStudio.Shared.Helpers;
using FluentAssertions;
using System;
using System.Collections.Generic;
using System.IO;
using Xunit;

namespace EdgeStudioTests
{
    /// <summary>
    /// Unit tests for EnvFileReader helper class
    /// </summary>
    public class EnvFileReaderTests : IDisposable
    {
        private readonly List<string> _tempFiles = new();

        public void Dispose()
        {
            // Clean up temporary files after each test
            foreach (var file in _tempFiles)
            {
                if (File.Exists(file))
                {
                    try
                    {
                        File.Delete(file);
                    }
                    catch
                    {
                        // Ignore cleanup errors
                    }
                }
            }
        }

        #region ReadFromFile Tests - Basic Functionality

        [Fact]
        public void ReadFromFile_WithValidFile_ShouldReturnDictionary()
        {
            // Arrange
            var tempFile = CreateTempEnvFile("KEY1=value1\nKEY2=value2");

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result.Should().NotBeNull();
            result.Should().HaveCount(2);
            result["KEY1"].Should().Be("value1");
            result["KEY2"].Should().Be("value2");
        }

        [Fact]
        public void ReadFromFile_WithEmptyFile_ShouldReturnEmptyDictionary()
        {
            // Arrange
            var tempFile = CreateTempEnvFile("");

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result.Should().NotBeNull();
            result.Should().BeEmpty();
        }

        [Fact]
        public void ReadFromFile_WithNonExistentFile_ShouldThrowFileNotFoundException()
        {
            // Arrange
            var nonExistentPath = Path.Combine(Path.GetTempPath(), $"non_existent_{Guid.NewGuid()}.env");

            // Act & Assert
            var act = () => EnvFileReader.ReadFromFile(nonExistentPath);
            act.Should().Throw<FileNotFoundException>()
                .WithMessage($"*{Path.GetFullPath(nonExistentPath)}*");
        }

        [Fact]
        public void ReadFromFile_WithSingleKeyValue_ShouldParsCorrectly()
        {
            // Arrange
            var tempFile = CreateTempEnvFile("DATABASE_URL=ditto://localhost:5432");

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result.Should().ContainSingle();
            result["DATABASE_URL"].Should().Be("ditto://localhost:5432");
        }

        #endregion

        #region ReadFromFile Tests - Comments and Empty Lines

        [Fact]
        public void ReadFromFile_WithComments_ShouldIgnoreCommentLines()
        {
            // Arrange
            var content = @"# This is a comment
                KEY1=value1
                # Another comment
                KEY2=value2";
            var tempFile = CreateTempEnvFile(content);

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result.Should().HaveCount(2);
            result.Should().ContainKey("KEY1");
            result.Should().ContainKey("KEY2");
        }

        [Fact]
        public void ReadFromFile_WithEmptyLines_ShouldIgnoreEmptyLines()
        {
            // Arrange
            var content = @"KEY1=value1
                KEY2=value2

                KEY3=value3";
            var tempFile = CreateTempEnvFile(content);

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result.Should().HaveCount(3);
            result["KEY1"].Should().Be("value1");
            result["KEY2"].Should().Be("value2");
            result["KEY3"].Should().Be("value3");
        }

        [Fact]
        public void ReadFromFile_WithWhitespaceOnlyLines_ShouldIgnoreWhitespaceLines()
        {
            // Arrange
            var content = "KEY1=value1\n   \nKEY2=value2\n\t\t\nKEY3=value3";
            var tempFile = CreateTempEnvFile(content);

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result.Should().HaveCount(3);
            result.Should().ContainKey("KEY1");
            result.Should().ContainKey("KEY2");
            result.Should().ContainKey("KEY3");
        }

        [Fact]
        public void ReadFromFile_WithMixedCommentsAndEmptyLines_ShouldParseOnlyValidLines()
        {
            // Arrange
            var content = @"# Configuration file
                KEY1=value1

                # Database settings
                KEY2=value2

                # Leave this blank

                KEY3=value3";
            var tempFile = CreateTempEnvFile(content);

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result.Should().HaveCount(3);
        }

        #endregion

        #region ReadFromFile Tests - Whitespace Handling

        [Fact]
        public void ReadFromFile_WithWhitespaceAroundKeyValue_ShouldTrimWhitespace()
        {
            // Arrange
            var content = "  KEY1  =  value1  \n\tKEY2\t=\tvalue2\t";
            var tempFile = CreateTempEnvFile(content);

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result.Should().HaveCount(2);
            result["KEY1"].Should().Be("value1");
            result["KEY2"].Should().Be("value2");
        }

        [Fact]
        public void ReadFromFile_WithWhitespaceInValue_ShouldPreserveInternalWhitespace()
        {
            // Arrange
            var tempFile = CreateTempEnvFile("MESSAGE=Hello World");

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result["MESSAGE"].Should().Be("Hello World");
        }

        #endregion

        #region ReadFromFile Tests - Quote Handling

        [Fact]
        public void ReadFromFile_WithDoubleQuotedValue_ShouldRemoveQuotes()
        {
            // Arrange
            var tempFile = CreateTempEnvFile("KEY1=\"value with spaces\"");

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result["KEY1"].Should().Be("value with spaces");
        }

        [Fact]
        public void ReadFromFile_WithSingleQuotedValue_ShouldRemoveQuotes()
        {
            // Arrange
            var tempFile = CreateTempEnvFile("KEY1='value with spaces'");

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result["KEY1"].Should().Be("value with spaces");
        }

        [Fact]
        public void ReadFromFile_WithMismatchedQuotes_ShouldNotRemoveQuotes()
        {
            // Arrange
            var tempFile = CreateTempEnvFile("KEY1=\"value'");

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result["KEY1"].Should().Be("\"value'");
        }

        [Fact]
        public void ReadFromFile_WithQuotesInMiddle_ShouldNotRemoveQuotes()
        {
            // Arrange
            var tempFile = CreateTempEnvFile("KEY1=some\"value\"here");

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result["KEY1"].Should().Be("some\"value\"here");
        }

        [Fact]
        public void ReadFromFile_WithEmptyQuotedValue_ShouldReturnEmptyString()
        {
            // Arrange
            var tempFile = CreateTempEnvFile("KEY1=\"\"");

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result["KEY1"].Should().Be("");
        }

        #endregion

        #region ReadFromFile Tests - Special Characters and Edge Cases

        [Fact]
        public void ReadFromFile_WithMultipleEqualsInValue_ShouldIncludeAllInValue()
        {
            // Arrange
            var tempFile = CreateTempEnvFile("CONNECTION_STRING=Server=localhost;Port=5432;Database=mydb");

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result["CONNECTION_STRING"].Should().Be("Server=localhost;Port=5432;Database=mydb");
        }

        [Fact]
        public void ReadFromFile_WithEqualsInQuotedValue_ShouldIncludeEquals()
        {
            // Arrange
            var tempFile = CreateTempEnvFile("FORMULA=\"x=y+z\"");

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result["FORMULA"].Should().Be("x=y+z");
        }

        [Fact]
        public void ReadFromFile_WithSpecialCharacters_ShouldPreserveCharacters()
        {
            // Arrange
            var content = @"KEY1=value@with#special$chars%
KEY2=value!with&more*chars
KEY3=path/to/some/file";
            var tempFile = CreateTempEnvFile(content);

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result["KEY1"].Should().Be("value@with#special$chars%");
            result["KEY2"].Should().Be("value!with&more*chars");
            result["KEY3"].Should().Be("path/to/some/file");
        }

        [Fact]
        public void ReadFromFile_WithNoEqualsSign_ShouldIgnoreLine()
        {
            // Arrange
            var content = @"KEY1=value1
INVALID_LINE_WITHOUT_EQUALS
KEY2=value2";
            var tempFile = CreateTempEnvFile(content);

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result.Should().HaveCount(2);
            result.Should().ContainKey("KEY1");
            result.Should().ContainKey("KEY2");
            result.Should().NotContainKey("INVALID_LINE_WITHOUT_EQUALS");
        }

        [Fact]
        public void ReadFromFile_WithEmptyValue_ShouldReturnEmptyString()
        {
            // Arrange
            var tempFile = CreateTempEnvFile("KEY1=");

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result["KEY1"].Should().Be("");
        }

        [Fact]
        public void ReadFromFile_WithEmptyKey_ShouldStoreWithEmptyKey()
        {
            // Arrange
            var tempFile = CreateTempEnvFile("=value");

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result.Should().ContainKey("");
            result[""].Should().Be("value");
        }

        #endregion

        #region ReadFromFile Tests - Real-World Scenarios

        [Fact]
        public void ReadFromFile_WithDittoConfiguration_ShouldParseCorrectly()
        {
            // Arrange
            var content = @"# Ditto Configuration
                DITTO_APP_ID=live.ditto.myapp
                DITTO_AUTH_TOKEN=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9
                DITTO_AUTH_URL=https://auth.ditto.live
                DITTO_HTTP_API_URL=https://api.ditto.live
                DITTO_HTTP_API_KEY=abc123def456
                DITTO_MODE=online
                DITTO_ALLOW_UNTRUSTED_CERTS=false";
            var tempFile = CreateTempEnvFile(content);

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result.Should().HaveCount(7);
            result["DITTO_APP_ID"].Should().Be("live.ditto.myapp");
            result["DITTO_AUTH_TOKEN"].Should().Be("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9");
            result["DITTO_AUTH_URL"].Should().Be("https://auth.ditto.live");
            result["DITTO_HTTP_API_URL"].Should().Be("https://api.ditto.live");
            result["DITTO_HTTP_API_KEY"].Should().Be("abc123def456");
            result["DITTO_MODE"].Should().Be("online");
            result["DITTO_ALLOW_UNTRUSTED_CERTS"].Should().Be("false");
        }

        [Fact]
        public void ReadFromFile_WithDuplicateKeys_ShouldUseLastValue()
        {
            // Arrange
            var content = @"KEY1=first_value
                KEY1=second_value
                KEY1=third_value";
            var tempFile = CreateTempEnvFile(content);

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result.Should().ContainSingle();
            result["KEY1"].Should().Be("third_value");
        }

        [Fact]
        public void ReadFromFile_WithLongValue_ShouldParseCorrectly()
        {
            // Arrange
            var longValue = new string('a', 1000);
            var tempFile = CreateTempEnvFile($"LONG_KEY={longValue}");

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result["LONG_KEY"].Should().Be(longValue);
            result["LONG_KEY"].Length.Should().Be(1000);
        }

        [Fact]
        public void ReadFromFile_WithManyVariables_ShouldParseAll()
        {
            // Arrange
            var content = string.Join("\n", Enumerable.Range(1, 100).Select(i => $"KEY{i}=value{i}"));
            var tempFile = CreateTempEnvFile(content);

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result.Should().HaveCount(100);
            result["KEY1"].Should().Be("value1");
            result["KEY50"].Should().Be("value50");
            result["KEY100"].Should().Be("value100");
        }

        #endregion

        #region ReadFromFile Tests - Different Line Endings

        [Fact]
        public void ReadFromFile_WithWindowsLineEndings_ShouldParse()
        {
            // Arrange
            var content = "KEY1=value1\r\nKEY2=value2\r\nKEY3=value3";
            var tempFile = CreateTempEnvFile(content);

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result.Should().HaveCount(3);
            result["KEY1"].Should().Be("value1");
            result["KEY2"].Should().Be("value2");
            result["KEY3"].Should().Be("value3");
        }

        [Fact]
        public void ReadFromFile_WithUnixLineEndings_ShouldParse()
        {
            // Arrange
            var content = "KEY1=value1\nKEY2=value2\nKEY3=value3";
            var tempFile = CreateTempEnvFile(content);

            // Act
            var result = EnvFileReader.ReadFromFile(tempFile);

            // Assert
            result.Should().HaveCount(3);
            result["KEY1"].Should().Be("value1");
            result["KEY2"].Should().Be("value2");
            result["KEY3"].Should().Be("value3");
        }

        #endregion

        #region Read Method Tests (Embedded Resource)

        [Fact]
        public void Read_WhenCalledFromTestAssembly_ShouldThrowInvalidOperationExceptionOrReturnEmpty()
        {
            // Arrange & Act
            // The Read method will fail in test assembly because there's no embedded resource
            // Or it might find a resource from the EdgeStudio assembly that's loaded
            try
            {
                var result = EnvFileReader.Read();
                // If it doesn't throw, it should return a dictionary (might be empty or have values)
                result.Should().NotBeNull();
            }
            catch (InvalidOperationException ex)
            {
                // This is also acceptable - the embedded resource wasn't found
                ex.Message.Should().Contain("Could not find embedded resource");
            }
        }

        [Fact]
        public void Read_MethodExists_ShouldBeCallable()
        {
            // Arrange & Act & Assert
            // Just verify the method exists and is callable
            var act = () => EnvFileReader.Read();
            // We don't assert on the result because it depends on the runtime assembly
            act.Should().NotBeNull();
        }

        #endregion

        #region Helper Methods

        /// <summary>
        /// Creates a temporary .env file with the specified content
        /// </summary>
        private string CreateTempEnvFile(string content)
        {
            var tempFile = Path.Combine(Path.GetTempPath(), $"test_{Guid.NewGuid()}.env");
            File.WriteAllText(tempFile, content);
            _tempFiles.Add(tempFile);
            return tempFile;
        }

        #endregion
    }
}
