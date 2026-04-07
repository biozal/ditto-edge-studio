using System.Linq;
using System.Text.RegularExpressions;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Messages;
using EdgeStudio.Shared.Models;
using EdgeStudio.ViewModels;
using FluentAssertions;
using Moq;
using Xunit;

namespace EdgeStudioTests;

#region AttachmentInfo Model Tests

public class AttachmentInfoTests
{
    [Fact]
    public void DetectTokens_WithValidAttachment_ReturnsCorrectInfo()
    {
        var json = """
            {
                "_id": "123",
                "photo": {
                    "id": "abc",
                    "len": 1024,
                    "metadata": { "name": "test.png", "mimeType": "image/png" }
                }
            }
            """;

        var tokens = AttachmentInfo.DetectTokens(json);

        tokens.Should().HaveCount(1);
        tokens[0].FieldName.Should().Be("photo");
        tokens[0].Id.Should().Be("abc");
        tokens[0].Length.Should().Be(1024);
        tokens[0].IsImage.Should().BeTrue();
        tokens[0].FileName.Should().Be("test.png");
        tokens[0].MimeType.Should().Be("image/png");
    }

    [Fact]
    public void DetectTokens_WithNoAttachmentTokens_ReturnsEmptyList()
    {
        var json = """{"_id": "123", "name": "Alice", "age": 30}""";

        var tokens = AttachmentInfo.DetectTokens(json);

        tokens.Should().BeEmpty();
    }

    [Fact]
    public void DetectTokens_WithMultipleAttachmentFields_ReturnsAll()
    {
        var json = """
            {
                "_id": "doc1",
                "photo": {
                    "id": "att1",
                    "len": 2048,
                    "metadata": { "name": "photo.jpg", "mimeType": "image/jpeg" }
                },
                "document": {
                    "id": "att2",
                    "len": 51200,
                    "metadata": { "name": "report.pdf", "mimeType": "application/pdf" }
                }
            }
            """;

        var tokens = AttachmentInfo.DetectTokens(json);

        tokens.Should().HaveCount(2);
        tokens.Should().Contain(t => t.FieldName == "photo" && t.Id == "att1");
        tokens.Should().Contain(t => t.FieldName == "document" && t.Id == "att2");
    }

    [Fact]
    public void DetectTokens_WithInvalidJson_ReturnsEmptyList()
    {
        var tokens = AttachmentInfo.DetectTokens("not valid json {{{");

        tokens.Should().BeEmpty();
    }

    [Fact]
    public void DetectTokens_ObjectMissingMetadata_IsNotDetected()
    {
        var json = """
            {
                "_id": "123",
                "partial": {
                    "id": "abc",
                    "len": 1024
                }
            }
            """;

        var tokens = AttachmentInfo.DetectTokens(json);

        tokens.Should().BeEmpty();
    }

    [Fact]
    public void DetectTokens_ObjectMissingId_IsNotDetected()
    {
        var json = """
            {
                "_id": "123",
                "partial": {
                    "len": 1024,
                    "metadata": { "name": "test.png" }
                }
            }
            """;

        var tokens = AttachmentInfo.DetectTokens(json);

        tokens.Should().BeEmpty();
    }

    [Fact]
    public void DetectTokens_ObjectMissingLen_IsNotDetected()
    {
        var json = """
            {
                "_id": "123",
                "partial": {
                    "id": "abc",
                    "metadata": { "name": "test.png" }
                }
            }
            """;

        var tokens = AttachmentInfo.DetectTokens(json);

        tokens.Should().BeEmpty();
    }

    [Fact]
    public void IsImage_WithImageMimeType_ReturnsTrue()
    {
        var info = new AttachmentInfo
        {
            Id = "x",
            FieldName = "photo",
            Length = 100,
            Metadata = new() { ["mimeType"] = "image/png" }
        };

        info.IsImage.Should().BeTrue();
    }

    [Fact]
    public void IsImage_WithNonImageMimeType_ReturnsFalse()
    {
        var info = new AttachmentInfo
        {
            Id = "x",
            FieldName = "file",
            Length = 100,
            Metadata = new() { ["mimeType"] = "text/plain" }
        };

        info.IsImage.Should().BeFalse();
    }

    [Fact]
    public void IsImage_WithNoMimeType_ReturnsFalse()
    {
        var info = new AttachmentInfo
        {
            Id = "x",
            FieldName = "file",
            Length = 100,
            Metadata = new()
        };

        info.IsImage.Should().BeFalse();
    }

    [Theory]
    [InlineData(0, "0 B")]
    [InlineData(512, "512 B")]
    [InlineData(1024, "1 KB")]
    [InlineData(1536, "1.5 KB")]
    [InlineData(1048576, "1 MB")]
    [InlineData(1073741824, "1 GB")]
    public void FormattedSize_ReturnsReadableString(long bytes, string expected)
    {
        var info = new AttachmentInfo
        {
            Id = "x",
            FieldName = "f",
            Length = bytes,
            Metadata = new()
        };

        info.FormattedSize.Should().Be(expected);
    }

    [Fact]
    public void FileName_ExtractsFromMetadata_NameKey()
    {
        var info = new AttachmentInfo
        {
            Id = "x",
            FieldName = "f",
            Metadata = new() { ["name"] = "report.pdf" }
        };

        info.FileName.Should().Be("report.pdf");
    }

    [Fact]
    public void FileName_ExtractsFromMetadata_FileNameKey()
    {
        var info = new AttachmentInfo
        {
            Id = "x",
            FieldName = "f",
            Metadata = new() { ["fileName"] = "report.pdf" }
        };

        info.FileName.Should().Be("report.pdf");
    }

    [Fact]
    public void FileName_ExtractsFromMetadata_FileNameSnakeCaseKey()
    {
        var info = new AttachmentInfo
        {
            Id = "x",
            FieldName = "f",
            Metadata = new() { ["file_name"] = "report.pdf" }
        };

        info.FileName.Should().Be("report.pdf");
    }

    [Fact]
    public void MimeType_ExtractsFromMetadata_TypeKey()
    {
        var info = new AttachmentInfo
        {
            Id = "x",
            FieldName = "f",
            Metadata = new() { ["type"] = "application/json" }
        };

        info.MimeType.Should().Be("application/json");
    }

    [Fact]
    public void MimeType_ExtractsFromMetadata_MimeTypeSnakeCaseKey()
    {
        var info = new AttachmentInfo
        {
            Id = "x",
            FieldName = "f",
            Metadata = new() { ["mime_type"] = "text/html" }
        };

        info.MimeType.Should().Be("text/html");
    }
}

#endregion

#region AttachmentService SafeIdentifier Validation Tests

public class AttachmentServiceIdentifierTests
{
    // Same regex used internally by AttachmentService.SafeIdentifier
    private static readonly Regex SafeIdentifier = new(@"^[a-zA-Z_][a-zA-Z0-9_]*$", RegexOptions.Compiled);

    [Theory]
    [InlineData("photo", true)]
    [InlineData("my_field", true)]
    [InlineData("field123", true)]
    [InlineData("_private", true)]
    [InlineData("A", true)]
    [InlineData("camelCase", true)]
    public void SafeIdentifier_ValidNames_Match(string name, bool expected)
    {
        SafeIdentifier.IsMatch(name).Should().Be(expected);
    }

    [Theory]
    [InlineData("")]
    [InlineData("has spaces")]
    [InlineData("drop;--")]
    [InlineData("123start")]
    [InlineData("field-name")]
    [InlineData("field.name")]
    [InlineData("field/name")]
    public void SafeIdentifier_InvalidNames_DoNotMatch(string name)
    {
        SafeIdentifier.IsMatch(name).Should().BeFalse();
    }
}

#endregion

#region AttachmentViewModel Tests

public class AttachmentViewModelTests
{
    private readonly Mock<IAttachmentService> _mockService = new();

    private AttachmentViewModel CreateSut() => new(_mockService.Object);

    [Fact]
    public void DetectAttachments_WithTokens_PopulatesDetectedAttachments()
    {
        var sut = CreateSut();
        var json = """
            {
                "_id": "doc1",
                "photo": {
                    "id": "att1",
                    "len": 2048,
                    "metadata": { "name": "pic.png", "mimeType": "image/png" }
                }
            }
            """;

        sut.DetectAttachments(json);

        sut.DetectedAttachments.Should().HaveCount(1);
        sut.DetectedAttachments[0].FieldName.Should().Be("photo");
        sut.DetectedAttachments[0].Id.Should().Be("att1");
    }

    [Fact]
    public void DetectAttachments_WithNull_ClearsDetectedAttachments()
    {
        var sut = CreateSut();
        // First populate
        var json = """
            {
                "_id": "doc1",
                "photo": {
                    "id": "att1",
                    "len": 2048,
                    "metadata": { "name": "pic.png", "mimeType": "image/png" }
                }
            }
            """;
        sut.DetectAttachments(json);
        sut.DetectedAttachments.Should().NotBeEmpty();

        // Now clear
        sut.DetectAttachments(null);

        sut.DetectedAttachments.Should().BeEmpty();
    }

    [Fact]
    public void DetectAttachments_ClearsPreviousResults_WhenCalledWithNewJson()
    {
        var sut = CreateSut();

        var json1 = """
            {
                "_id": "doc1",
                "photo": {
                    "id": "att1",
                    "len": 1024,
                    "metadata": { "name": "a.png", "mimeType": "image/png" }
                }
            }
            """;
        sut.DetectAttachments(json1);
        sut.DetectedAttachments.Should().HaveCount(1);
        sut.DetectedAttachments[0].Id.Should().Be("att1");

        var json2 = """
            {
                "_id": "doc2",
                "avatar": {
                    "id": "att2",
                    "len": 512,
                    "metadata": { "name": "b.jpg", "mimeType": "image/jpeg" }
                }
            }
            """;
        sut.DetectAttachments(json2);

        sut.DetectedAttachments.Should().HaveCount(1);
        sut.DetectedAttachments[0].FieldName.Should().Be("avatar");
        sut.DetectedAttachments[0].Id.Should().Be("att2");
    }

    [Fact]
    public void DetectAttachments_JsonWithoutTokens_ReturnsEmpty()
    {
        var sut = CreateSut();

        sut.DetectAttachments("""{"_id": "doc1", "name": "test"}""");

        sut.DetectedAttachments.Should().BeEmpty();
    }

    [Fact]
    public void DetectAttachments_WithWhitespace_ClearsDetectedAttachments()
    {
        var sut = CreateSut();

        sut.DetectAttachments("   ");

        sut.DetectedAttachments.Should().BeEmpty();
    }
}

#endregion

#region Collection Name Parsing Tests

public class CollectionNameParsingTests
{
    // Same regex used by QueryDocumentViewModel.ParseCollectionName
    private static string? ParseCollectionName(string query)
    {
        var match = Regex.Match(query, @"\bFROM\s+(\w+)", RegexOptions.IgnoreCase);
        return match.Success ? match.Groups[1].Value : null;
    }

    [Theory]
    [InlineData("SELECT * FROM cars", "cars")]
    [InlineData("select * from Cars", "Cars")]
    [InlineData("SELECT * FROM users WHERE age > 21", "users")]
    [InlineData("SELECT _id, name FROM products LIMIT 10", "products")]
    [InlineData("select count(*) from my_collection", "my_collection")]
    public void ParseCollectionName_WithFromClause_ReturnsCollectionName(string query, string expected)
    {
        ParseCollectionName(query).Should().Be(expected);
    }

    [Theory]
    [InlineData("INSERT INTO cars")]
    [InlineData("UPDATE cars SET name = 'test'")]
    [InlineData("")]
    [InlineData("just some text")]
    public void ParseCollectionName_WithoutFromClause_ReturnsNull(string query)
    {
        ParseCollectionName(query).Should().BeNull();
    }
}

#endregion

#region QueryDocumentViewModel Attachment Tests

public class QueryDocumentViewModelAttachmentTests
{
    [Fact]
    public void OpenAttachmentCommand_IsNotNull()
    {
        var sut = new QueryDocumentViewModel();
        sut.OpenAttachmentCommand.Should().NotBeNull();
    }

    [Fact]
    public void SettingSelectedDocumentJson_WithAttachmentToken_PopulatesDetectedAttachments()
    {
        var sut = new QueryDocumentViewModel();
        sut.SelectedDocumentJson = """
        {
            "_id": "doc1",
            "photo": {
                "id": "att1",
                "len": 2048,
                "metadata": { "name": "pic.png", "mimeType": "image/png" }
            }
        }
        """;

        sut.DetectedAttachments.Should().HaveCount(1);
        sut.HasAttachments.Should().BeTrue();
        sut.DetectedAttachments[0].FieldName.Should().Be("photo");
    }

    [Fact]
    public void SettingSelectedDocumentJson_ToNull_ClearsDetectedAttachments()
    {
        var sut = new QueryDocumentViewModel();
        sut.SelectedDocumentJson = """{"_id":"1","f":{"id":"a","len":1,"metadata":{}}}""";
        sut.DetectedAttachments.Should().NotBeEmpty();

        sut.SelectedDocumentJson = null;

        sut.DetectedAttachments.Should().BeEmpty();
        sut.HasAttachments.Should().BeFalse();
    }

    [Fact]
    public async Task OpenAttachmentCommand_WithService_FetchesAttachment()
    {
        var mockService = new Mock<IAttachmentService>();
        mockService.Setup(s => s.FetchAsync(It.IsAny<Dictionary<string, object>>()))
                   .ReturnsAsync(new byte[] { 0x89, 0x50, 0x4E, 0x47 });

        var sut = new QueryDocumentViewModel(
            "test", null, null, null, null, "",
            null, null, mockService.Object);

        var attachment = new AttachmentInfo
        {
            Id = "att1", FieldName = "photo", Length = 4,
            Metadata = new() { ["name"] = "test.png", ["mimeType"] = "image/png" }
        };

        await sut.OpenAttachmentCommand.ExecuteAsync(attachment);

        mockService.Verify(s => s.FetchAsync(It.Is<Dictionary<string, object>>(d =>
            d.ContainsKey("id") && d["id"].Equals("att1") &&
            d.ContainsKey("metadata") && d["metadata"] is Dictionary<string, object>
        )), Times.Once);
    }

    [Fact]
    public async Task OpenAttachmentCommand_WithoutService_DoesNotThrow()
    {
        var sut = new QueryDocumentViewModel();

        var attachment = new AttachmentInfo
        {
            Id = "att1", FieldName = "photo", Length = 4,
            Metadata = new() { ["name"] = "test.png" }
        };

        // Should silently return, not throw
        await sut.OpenAttachmentCommand.ExecuteAsync(attachment);
    }

    [Fact]
    public void SettingSelectedDocumentJson_WithMultipleAttachments_DetectsAll()
    {
        var sut = new QueryDocumentViewModel();
        sut.SelectedDocumentJson = """
        {
            "_id": "doc1",
            "photo": {
                "id": "att1",
                "len": 2048,
                "metadata": { "name": "pic.png", "mimeType": "image/png" }
            },
            "resume": {
                "id": "att2",
                "len": 51200,
                "metadata": { "name": "resume.pdf", "mimeType": "application/pdf" }
            }
        }
        """;

        sut.DetectedAttachments.Should().HaveCount(2);
        sut.HasAttachments.Should().BeTrue();
    }

    [Fact]
    public void SettingSelectedDocumentJson_ReplacesExistingDetectedAttachments()
    {
        var sut = new QueryDocumentViewModel();

        sut.SelectedDocumentJson = """
        {
            "_id": "doc1",
            "photo": { "id": "att1", "len": 100, "metadata": { "name": "a.png" } }
        }
        """;
        sut.DetectedAttachments.Should().HaveCount(1);
        sut.DetectedAttachments[0].Id.Should().Be("att1");

        sut.SelectedDocumentJson = """
        {
            "_id": "doc2",
            "avatar": { "id": "att2", "len": 200, "metadata": { "name": "b.jpg" } }
        }
        """;
        sut.DetectedAttachments.Should().HaveCount(1);
        sut.DetectedAttachments[0].Id.Should().Be("att2");
    }
}

#endregion

#region Delete Attachment Flow Tests

public class DeleteAttachmentFlowTests
{
    [Fact]
    public void DeleteAttachmentRequestedMessage_CreatesWithCorrectProperties()
    {
        var msg = new DeleteAttachmentRequestedMessage(
            DocumentJson: """{"_id":"doc1","photo":{"id":"a","len":1,"metadata":{}}}""",
            Collection: "tasks",
            QueryMode: "Local");

        msg.DocumentJson.Should().Contain("doc1");
        msg.Collection.Should().Be("tasks");
        msg.QueryMode.Should().Be("Local");
    }

    [Fact]
    public void JsonResultsViewModel_DeleteAttachmentCommand_FiresEvent()
    {
        var vm = new JsonResultsViewModel();
        string? receivedJson = null;
        vm.DeleteAttachmentRequested += json => receivedJson = json;

        vm.DeleteAttachmentCommand.Execute("""{"_id":"1"}""");

        receivedJson.Should().Be("""{"_id":"1"}""");
    }

    [Fact]
    public void DetectTokens_UsedForDeleteDialog_FindsAttachmentFields()
    {
        var json = """
        {
            "_id": "doc1",
            "name": "test",
            "photo": { "id": "att1", "len": 2048, "metadata": { "name": "pic.png", "mimeType": "image/png" } },
            "resume": { "id": "att2", "len": 51200, "metadata": { "name": "resume.pdf", "mimeType": "application/pdf" } }
        }
        """;

        var tokens = AttachmentInfo.DetectTokens(json);

        tokens.Should().HaveCount(2);
        tokens.Select(t => t.FieldName).Should().Contain("photo").And.Contain("resume");
    }

    [Theory]
    [InlineData("photo", true)]
    [InlineData("my_field", true)]
    [InlineData("_private", true)]
    [InlineData("drop;--", false)]
    [InlineData("field name", false)]
    [InlineData("123start", false)]
    public void SafeIdentifier_ValidatesFieldNames(string name, bool expected)
    {
        var regex = new System.Text.RegularExpressions.Regex(@"^[a-zA-Z_][a-zA-Z0-9_]*$");
        regex.IsMatch(name).Should().Be(expected);
    }
}

#endregion
