using EdgeStudio.Models;

namespace EdgeStudioTests.Models
{
    [TestClass]
    public class DatabaseFormModelTests
    {
        private DatabaseFormModel _model = null!;

        [TestInitialize]
        public void Setup()
        {
            _model = new DatabaseFormModel();
        }

        [TestMethod]
        public void Constructor_InitializesPropertiesToDefaults()
        {
            // Assert
            Assert.AreEqual(string.Empty, _model.Id);
            Assert.AreEqual(string.Empty, _model.Name);
            Assert.AreEqual(string.Empty, _model.DatabaseId);
            Assert.AreEqual(string.Empty, _model.AuthToken);
            Assert.AreEqual(string.Empty, _model.AuthUrl);
            Assert.AreEqual(string.Empty, _model.HttpApiUrl);
            Assert.AreEqual(string.Empty, _model.HttpApiKey);
            Assert.AreEqual("default", _model.Mode);
            Assert.IsFalse(_model.AllowUntrustedCerts);
            Assert.IsFalse(_model.IsEditMode);
        }

        [TestMethod]
        public void Properties_SetAndGetValues_WorkCorrectly()
        {
            // Arrange & Act
            _model.Id = "test-id";
            _model.Name = "Test Database";
            _model.DatabaseId = "db-123";
            _model.AuthToken = "token-abc";
            _model.AuthUrl = "https://auth.example.com";
            _model.HttpApiUrl = "https://api.example.com";
            _model.HttpApiKey = "api-key-xyz";
            _model.Mode = "production";
            _model.AllowUntrustedCerts = true;
            _model.IsEditMode = true;

            // Assert
            Assert.AreEqual("test-id", _model.Id);
            Assert.AreEqual("Test Database", _model.Name);
            Assert.AreEqual("db-123", _model.DatabaseId);
            Assert.AreEqual("token-abc", _model.AuthToken);
            Assert.AreEqual("https://auth.example.com", _model.AuthUrl);
            Assert.AreEqual("https://api.example.com", _model.HttpApiUrl);
            Assert.AreEqual("api-key-xyz", _model.HttpApiKey);
            Assert.AreEqual("production", _model.Mode);
            Assert.IsTrue(_model.AllowUntrustedCerts);
            Assert.IsTrue(_model.IsEditMode);
        }

        [TestMethod]
        public void Reset_ClearsAllPropertiesToDefaults()
        {
            // Arrange - set some values
            _model.Id = "test-id";
            _model.Name = "Test Database";
            _model.DatabaseId = "db-123";
            _model.AuthToken = "token-abc";
            _model.AuthUrl = "https://auth.example.com";
            _model.HttpApiUrl = "https://api.example.com";
            _model.HttpApiKey = "api-key-xyz";
            _model.Mode = "production";
            _model.AllowUntrustedCerts = true;
            _model.IsEditMode = true;

            // Act
            _model.Reset();

            // Assert
            Assert.AreEqual(string.Empty, _model.Id);
            Assert.AreEqual(string.Empty, _model.Name);
            Assert.AreEqual(string.Empty, _model.DatabaseId);
            Assert.AreEqual(string.Empty, _model.AuthToken);
            Assert.AreEqual(string.Empty, _model.AuthUrl);
            Assert.AreEqual(string.Empty, _model.HttpApiUrl);
            Assert.AreEqual(string.Empty, _model.HttpApiKey);
            Assert.AreEqual("default", _model.Mode);
            Assert.IsFalse(_model.AllowUntrustedCerts);
            Assert.IsFalse(_model.IsEditMode);
        }

        [TestMethod]
        public void LoadFromConfig_CopiesAllPropertiesFromConfig()
        {
            // Arrange
            var config = CreateTestDatabaseConfig();

            // Act
            _model.LoadFromConfig(config);

            // Assert
            Assert.AreEqual(config.Id, _model.Id);
            Assert.AreEqual(config.Name, _model.Name);
            Assert.AreEqual(config.DatabaseId, _model.DatabaseId);
            Assert.AreEqual(config.AuthToken, _model.AuthToken);
            Assert.AreEqual(config.AuthUrl, _model.AuthUrl);
            Assert.AreEqual(config.HttpApiUrl, _model.HttpApiUrl);
            Assert.AreEqual(config.HttpApiKey, _model.HttpApiKey);
            Assert.AreEqual(config.Mode, _model.Mode);
            Assert.AreEqual(config.AllowUntrustedCerts, _model.AllowUntrustedCerts);
            Assert.IsTrue(_model.IsEditMode);
        }

        [TestMethod]
        public void ToConfig_CreatesConfigFromModelProperties()
        {
            // Arrange
            _model.Id = "test-id";
            _model.Name = "Test Database";
            _model.DatabaseId = "db-123";
            _model.AuthToken = "token-abc";
            _model.AuthUrl = "https://auth.example.com";
            _model.HttpApiUrl = "https://api.example.com";
            _model.HttpApiKey = "api-key-xyz";
            _model.Mode = "production";
            _model.AllowUntrustedCerts = true;

            // Act
            var config = _model.ToConfig();

            // Assert
            Assert.AreEqual(_model.Id, config.Id);
            Assert.AreEqual(_model.Name, config.Name);
            Assert.AreEqual(_model.DatabaseId, config.DatabaseId);
            Assert.AreEqual(_model.AuthToken, config.AuthToken);
            Assert.AreEqual(_model.AuthUrl, config.AuthUrl);
            Assert.AreEqual(_model.HttpApiUrl, config.HttpApiUrl);
            Assert.AreEqual(_model.HttpApiKey, config.HttpApiKey);
            Assert.AreEqual(_model.Mode, config.Mode);
            Assert.AreEqual(_model.AllowUntrustedCerts, config.AllowUntrustedCerts);
        }

        [TestMethod]
        public void ToConfig_WithEmptyId_GeneratesNewGuid()
        {
            // Arrange
            _model.Id = string.Empty;
            _model.Name = "Test Database";
            _model.DatabaseId = "db-123";
            _model.AuthToken = "token-abc";
            _model.AuthUrl = "https://auth.example.com";

            // Act
            var config = _model.ToConfig();

            // Assert
            Assert.IsTrue(Guid.TryParse(config.Id, out _));
            Assert.AreNotEqual(string.Empty, config.Id);
        }

        [TestMethod]
        public void ToConfig_WithExistingId_PreservesId()
        {
            // Arrange
            var existingId = Guid.NewGuid().ToString();
            _model.Id = existingId;
            _model.Name = "Test Database";
            _model.DatabaseId = "db-123";
            _model.AuthToken = "token-abc";
            _model.AuthUrl = "https://auth.example.com";

            // Act
            var config = _model.ToConfig();

            // Assert
            Assert.AreEqual(existingId, config.Id);
        }

        [TestMethod]
        public void LoadFromConfig_ThenToConfig_PreservesAllData()
        {
            // Arrange
            var originalConfig = CreateTestDatabaseConfig();

            // Act
            _model.LoadFromConfig(originalConfig);
            var recreatedConfig = _model.ToConfig();

            // Assert
            Assert.AreEqual(originalConfig.Id, recreatedConfig.Id);
            Assert.AreEqual(originalConfig.Name, recreatedConfig.Name);
            Assert.AreEqual(originalConfig.DatabaseId, recreatedConfig.DatabaseId);
            Assert.AreEqual(originalConfig.AuthToken, recreatedConfig.AuthToken);
            Assert.AreEqual(originalConfig.AuthUrl, recreatedConfig.AuthUrl);
            Assert.AreEqual(originalConfig.HttpApiUrl, recreatedConfig.HttpApiUrl);
            Assert.AreEqual(originalConfig.HttpApiKey, recreatedConfig.HttpApiKey);
            Assert.AreEqual(originalConfig.Mode, recreatedConfig.Mode);
            Assert.AreEqual(originalConfig.AllowUntrustedCerts, recreatedConfig.AllowUntrustedCerts);
        }

        [TestMethod]
        public void PropertyChanged_WhenPropertyIsSet_RaisesNotification()
        {
            // Arrange
            var propertyChangedEvents = new List<string>();
            _model.PropertyChanged += (sender, e) =>
            {
                if (e.PropertyName != null)
                    propertyChangedEvents.Add(e.PropertyName);
            };

            // Act
            _model.Name = "New Name";
            _model.DatabaseId = "new-id";
            _model.AllowUntrustedCerts = true;

            // Assert
            Assert.IsTrue(propertyChangedEvents.Contains(nameof(_model.Name)));
            Assert.IsTrue(propertyChangedEvents.Contains(nameof(_model.DatabaseId)));
            Assert.IsTrue(propertyChangedEvents.Contains(nameof(_model.AllowUntrustedCerts)));
        }

        private static DittoDatabaseConfig CreateTestDatabaseConfig()
        {
            return new DittoDatabaseConfig(
                Id: Guid.NewGuid().ToString(),
                Name: "Test Database",
                DatabaseId: "test-db-id",
                AuthToken: "test-token",
                AuthUrl: "https://auth.test.example.com",
                HttpApiUrl: "https://api.test.example.com",
                HttpApiKey: "test-api-key",
                Mode: "test",
                AllowUntrustedCerts: true
            );
        }
    }
}