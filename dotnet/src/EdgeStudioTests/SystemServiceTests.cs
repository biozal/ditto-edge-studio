using EdgeStudio.Shared.Models;
using FluentAssertions;
using Moq;
using System.Collections.ObjectModel;
using EdgeStudio.Shared.Data.Repositories;

namespace EdgeStudioTests
{
    /// <summary>
    /// Unit tests for ISystemRepository interface
    /// </summary>
    public class SystemRepositoryTests
    {
        private readonly Mock<ISystemRepository> _mockSystemRepository;

        public SystemRepositoryTests()
        {
            _mockSystemRepository = new Mock<ISystemRepository>();
        }

        #region CloseSelectedDatabase Tests

        [Fact]
        public void CloseSelectedDatabase_ShouldCallMethod()
        {
            // Arrange
            _mockSystemRepository.Setup(s => s.CloseSelectedDatabase());

            // Act
            _mockSystemRepository.Object.CloseSelectedDatabase();

            // Assert
            _mockSystemRepository.Verify(s => s.CloseSelectedDatabase(), Times.Once);
        }

        [Fact]
        public void CloseSelectedDatabase_ShouldNotThrow()
        {
            // Arrange
            _mockSystemRepository.Setup(s => s.CloseSelectedDatabase());

            // Act
            var act = () => _mockSystemRepository.Object.CloseSelectedDatabase();

            // Assert
            act.Should().NotThrow();
        }

        [Fact]
        public void CloseSelectedDatabase_WhenNoDatabaseSelected_ShouldNotThrow()
        {
            // Arrange
            _mockSystemRepository.Setup(s => s.CloseSelectedDatabase());

            // Act
            var act = () => _mockSystemRepository.Object.CloseSelectedDatabase();

            // Assert
            act.Should().NotThrow();
            _mockSystemRepository.Verify(s => s.CloseSelectedDatabase(), Times.Once);
        }

        [Fact]
        public void CloseSelectedDatabase_OnError_ShouldThrowException()
        {
            // Arrange
            _mockSystemRepository.Setup(s => s.CloseSelectedDatabase())
                .Throws(new InvalidOperationException("Failed to close database"));

            // Act & Assert
            Assert.Throws<InvalidOperationException>(() => _mockSystemRepository.Object.CloseSelectedDatabase());
        }

        [Fact]
        public void CloseSelectedDatabase_MultipleCalls_ShouldNotThrow()
        {
            // Arrange
            _mockSystemRepository.Setup(s => s.CloseSelectedDatabase());

            // Act
            _mockSystemRepository.Object.CloseSelectedDatabase();
            var act = () => _mockSystemRepository.Object.CloseSelectedDatabase();

            // Assert
            act.Should().NotThrow();
            _mockSystemRepository.Verify(s => s.CloseSelectedDatabase(), Times.Exactly(2));
        }

        #endregion

        #region RegisterPeerCardObservers Tests

        [Fact]
        public void RegisterPeerCardObservers_ShouldCallMethod()
        {
            // Arrange
            var peerCards = new ObservableCollection<ObservablePeerCardInfo>
            {
                CreateTestPeerCard("peer-1", PeerCardType.Remote, "Connected"),
                CreateTestPeerCard("peer-2", PeerCardType.Server, "Connected")
            };
            Action<string> errorCallback = (msg) => { };

            _mockSystemRepository.Setup(s => s.RegisterPeerCardObservers(
                It.IsAny<ObservableCollection<ObservablePeerCardInfo>>(),
                It.IsAny<Action<string>>()));

            // Act
            _mockSystemRepository.Object.RegisterPeerCardObservers(peerCards, errorCallback);

            // Assert
            _mockSystemRepository.Verify(s => s.RegisterPeerCardObservers(
                It.Is<ObservableCollection<ObservablePeerCardInfo>>(c => c.Count == 2),
                It.IsAny<Action<string>>()), Times.Once);
        }

        [Fact]
        public void RegisterPeerCardObservers_WithNullCollection_ShouldThrowException()
        {
            // Arrange
            Action<string> errorCallback = (msg) => { };
            _mockSystemRepository.Setup(s => s.RegisterPeerCardObservers(null!, It.IsAny<Action<string>>()))
                .Throws(new ArgumentNullException("peerCards"));

            // Act & Assert
            Assert.Throws<ArgumentNullException>(
                () => _mockSystemRepository.Object.RegisterPeerCardObservers(null!, errorCallback));
        }

        [Fact]
        public void RegisterPeerCardObservers_WithNullErrorCallback_ShouldThrowException()
        {
            // Arrange
            var peerCards = new ObservableCollection<ObservablePeerCardInfo>();
            _mockSystemRepository.Setup(s => s.RegisterPeerCardObservers(It.IsAny<ObservableCollection<ObservablePeerCardInfo>>(), null!))
                .Throws(new ArgumentNullException("errorMessage"));

            // Act & Assert
            Assert.Throws<ArgumentNullException>(
                () => _mockSystemRepository.Object.RegisterPeerCardObservers(peerCards, null!));
        }

        [Fact]
        public void RegisterPeerCardObservers_WithEmptyCollection_ShouldNotThrow()
        {
            // Arrange
            var peerCards = new ObservableCollection<ObservablePeerCardInfo>();
            Action<string> errorCallback = (msg) => { };

            _mockSystemRepository.Setup(s => s.RegisterPeerCardObservers(
                It.IsAny<ObservableCollection<ObservablePeerCardInfo>>(),
                It.IsAny<Action<string>>()));

            // Act
            var act = () => _mockSystemRepository.Object.RegisterPeerCardObservers(peerCards, errorCallback);

            // Assert
            act.Should().NotThrow();
        }

        [Fact]
        public void RegisterPeerCardObservers_ErrorCallback_ShouldBeInvoked()
        {
            // Arrange
            var peerCards = new ObservableCollection<ObservablePeerCardInfo>();
            string? capturedError = null;
            Action<string> errorCallback = (msg) => { capturedError = msg; };

            _mockSystemRepository.Setup(s => s.RegisterPeerCardObservers(
                It.IsAny<ObservableCollection<ObservablePeerCardInfo>>(),
                It.IsAny<Action<string>>()))
                .Callback<ObservableCollection<ObservablePeerCardInfo>, Action<string>>((infos, callback) =>
                {
                    callback("Test error message");
                });

            // Act
            _mockSystemRepository.Object.RegisterPeerCardObservers(peerCards, errorCallback);

            // Assert
            capturedError.Should().Be("Test error message");
        }

        [Fact]
        public void RegisterPeerCardObservers_WithMultiplePeerCards_ShouldAcceptAll()
        {
            // Arrange
            var peerCards = new ObservableCollection<ObservablePeerCardInfo>
            {
                CreateTestPeerCard("peer-1", PeerCardType.Remote, "Connected"),
                CreateTestPeerCard("peer-2", PeerCardType.Server, "Connected"),
                CreateTestPeerCard("peer-3", PeerCardType.Remote, "Not Connected"),
                CreateTestPeerCard("server-1", PeerCardType.Server, "Connected")
            };
            Action<string> errorCallback = (msg) => { };

            _mockSystemRepository.Setup(s => s.RegisterPeerCardObservers(
                It.IsAny<ObservableCollection<ObservablePeerCardInfo>>(),
                It.IsAny<Action<string>>()));

            // Act
            var act = () => _mockSystemRepository.Object.RegisterPeerCardObservers(peerCards, errorCallback);

            // Assert
            act.Should().NotThrow();
            _mockSystemRepository.Verify(s => s.RegisterPeerCardObservers(
                It.Is<ObservableCollection<ObservablePeerCardInfo>>(c => c.Count == 4),
                It.IsAny<Action<string>>()), Times.Once);
        }

        [Fact]
        public void RegisterPeerCardObservers_WithDittoServerPeers_ShouldHandle()
        {
            // Arrange
            var peerCards = new ObservableCollection<ObservablePeerCardInfo>
            {
                CreateTestPeerCard("cloud-1", PeerCardType.Server, "Connected", isDittoServer: true),
                CreateTestPeerCard("cloud-2", PeerCardType.Server, "Connected", isDittoServer: true)
            };
            Action<string> errorCallback = (msg) => { };

            _mockSystemRepository.Setup(s => s.RegisterPeerCardObservers(
                It.IsAny<ObservableCollection<ObservablePeerCardInfo>>(),
                It.IsAny<Action<string>>()));

            // Act
            _mockSystemRepository.Object.RegisterPeerCardObservers(peerCards, errorCallback);

            // Assert
            peerCards[0].CardType.Should().Be(PeerCardType.Server);
            peerCards[0].IsDittoServer.Should().BeTrue();
            peerCards[1].CardType.Should().Be(PeerCardType.Server);
            peerCards[1].IsDittoServer.Should().BeTrue();
            _mockSystemRepository.Verify(s => s.RegisterPeerCardObservers(
                It.IsAny<ObservableCollection<ObservablePeerCardInfo>>(),
                It.IsAny<Action<string>>()), Times.Once);
        }

        [Fact]
        public void RegisterPeerCardObservers_WithRemotePeerDevices_ShouldHandle()
        {
            // Arrange
            var peerCards = new ObservableCollection<ObservablePeerCardInfo>
            {
                CreateTestPeerCard("device-1", PeerCardType.Remote, "Connected"),
                CreateTestPeerCard("device-2", PeerCardType.Remote, "Not Connected")
            };
            Action<string> errorCallback = (msg) => { };

            _mockSystemRepository.Setup(s => s.RegisterPeerCardObservers(
                It.IsAny<ObservableCollection<ObservablePeerCardInfo>>(),
                It.IsAny<Action<string>>()));

            // Act
            _mockSystemRepository.Object.RegisterPeerCardObservers(peerCards, errorCallback);

            // Assert
            peerCards[0].CardType.Should().Be(PeerCardType.Remote);
            peerCards[0].IsConnected.Should().BeTrue();
            peerCards[1].CardType.Should().Be(PeerCardType.Remote);
            peerCards[1].IsConnected.Should().BeFalse();
        }

        [Fact]
        public void RegisterPeerCardObservers_WithMixedConnectionStatus_ShouldHandle()
        {
            // Arrange
            var peerCards = new ObservableCollection<ObservablePeerCardInfo>
            {
                CreateTestPeerCard("peer-connected", PeerCardType.Remote, "Connected"),
                CreateTestPeerCard("peer-disconnected", PeerCardType.Remote, "Disconnected"),
                CreateTestPeerCard("peer-unknown", PeerCardType.Remote, "Unknown")
            };
            Action<string> errorCallback = (msg) => { };

            _mockSystemRepository.Setup(s => s.RegisterPeerCardObservers(
                It.IsAny<ObservableCollection<ObservablePeerCardInfo>>(),
                It.IsAny<Action<string>>()));

            // Act
            _mockSystemRepository.Object.RegisterPeerCardObservers(peerCards, errorCallback);

            // Assert
            peerCards[0].ConnectionStatus.Should().Be("Connected");
            peerCards[1].ConnectionStatus.Should().Be("Not Connected");
            peerCards[2].ConnectionStatus.Should().Be("Not Connected");
        }

        [Fact]
        public void RegisterPeerCardObservers_OnObserverError_ShouldInvokeErrorCallback()
        {
            // Arrange
            var peerCards = new ObservableCollection<ObservablePeerCardInfo>();
            var errorMessages = new List<string>();
            Action<string> errorCallback = (msg) => { errorMessages.Add(msg); };

            _mockSystemRepository.Setup(s => s.RegisterPeerCardObservers(
                It.IsAny<ObservableCollection<ObservablePeerCardInfo>>(),
                It.IsAny<Action<string>>()))
                .Callback<ObservableCollection<ObservablePeerCardInfo>, Action<string>>((infos, callback) =>
                {
                    callback("Observer registration failed");
                    callback("Connection error");
                });

            // Act
            _mockSystemRepository.Object.RegisterPeerCardObservers(peerCards, errorCallback);

            // Assert
            errorMessages.Should().HaveCount(2);
            errorMessages.Should().Contain("Observer registration failed");
            errorMessages.Should().Contain("Connection error");
        }

        [Fact]
        public void RegisterPeerCardObservers_MultipleCalls_ShouldAllowReregistration()
        {
            // Arrange
            var peerCards1 = new ObservableCollection<ObservablePeerCardInfo>
            {
                CreateTestPeerCard("peer-1", PeerCardType.Remote, "Connected")
            };
            var peerCards2 = new ObservableCollection<ObservablePeerCardInfo>
            {
                CreateTestPeerCard("peer-2", PeerCardType.Remote, "Connected")
            };
            Action<string> errorCallback = (msg) => { };

            _mockSystemRepository.Setup(s => s.RegisterPeerCardObservers(
                It.IsAny<ObservableCollection<ObservablePeerCardInfo>>(),
                It.IsAny<Action<string>>()));

            // Act
            _mockSystemRepository.Object.RegisterPeerCardObservers(peerCards1, errorCallback);
            _mockSystemRepository.Object.RegisterPeerCardObservers(peerCards2, errorCallback);

            // Assert
            _mockSystemRepository.Verify(s => s.RegisterPeerCardObservers(
                It.IsAny<ObservableCollection<ObservablePeerCardInfo>>(),
                It.IsAny<Action<string>>()), Times.Exactly(2));
        }

        [Fact]
        public void RegisterPeerCardObservers_WithLocalPeer_ShouldHandle()
        {
            // Arrange
            var peerCards = new ObservableCollection<ObservablePeerCardInfo>
            {
                CreateTestPeerCard("local-peer", PeerCardType.Local, null, deviceName: "My Device")
            };
            Action<string> errorCallback = (msg) => { };

            _mockSystemRepository.Setup(s => s.RegisterPeerCardObservers(
                It.IsAny<ObservableCollection<ObservablePeerCardInfo>>(),
                It.IsAny<Action<string>>()));

            // Act
            _mockSystemRepository.Object.RegisterPeerCardObservers(peerCards, errorCallback);

            // Assert
            peerCards[0].CardType.Should().Be(PeerCardType.Local);
            peerCards[0].DisplayName.Should().Be("My Device");
            _mockSystemRepository.Verify(s => s.RegisterPeerCardObservers(
                It.IsAny<ObservableCollection<ObservablePeerCardInfo>>(),
                It.IsAny<Action<string>>()), Times.Once);
        }

        #endregion

        #region Integration-Style Tests

        [Fact]
        public void FullLifecycle_RegisterObserversAndClose_ShouldWork()
        {
            // Arrange
            var peerCards = new ObservableCollection<ObservablePeerCardInfo>
            {
                CreateTestPeerCard("peer-1", PeerCardType.Remote, "Connected"),
                CreateTestPeerCard("server-1", PeerCardType.Server, "Connected")
            };
            Action<string> errorCallback = (msg) => { };

            _mockSystemRepository.Setup(s => s.RegisterPeerCardObservers(
                It.IsAny<ObservableCollection<ObservablePeerCardInfo>>(),
                It.IsAny<Action<string>>()));
            _mockSystemRepository.Setup(s => s.CloseSelectedDatabase());

            // Act & Assert - Register Observers
            var registerAct = () => _mockSystemRepository.Object.RegisterPeerCardObservers(peerCards, errorCallback);
            registerAct.Should().NotThrow();

            // Act & Assert - Close Database
            var closeAct = () => _mockSystemRepository.Object.CloseSelectedDatabase();
            closeAct.Should().NotThrow();

            // Verify methods were called
            _mockSystemRepository.Verify(s => s.RegisterPeerCardObservers(
                It.IsAny<ObservableCollection<ObservablePeerCardInfo>>(),
                It.IsAny<Action<string>>()), Times.Once);
            _mockSystemRepository.Verify(s => s.CloseSelectedDatabase(), Times.Once);
        }

        #endregion

        #region PeerCardInfo Model Tests

        [Fact]
        public void PeerCardInfo_ServerCard_ShouldHaveCorrectProperties()
        {
            // Arrange & Act
            var peerCard = CreateTestPeerCardInfo("server-1", PeerCardType.Server, "Connected", isDittoServer: true);

            // Assert
            peerCard.CardType.Should().Be(PeerCardType.Server);
            peerCard.IsDittoServer.Should().BeTrue();
            peerCard.DisplayName.Should().Be("Server");
            peerCard.IsConnected.Should().BeTrue();
            peerCard.ConnectionStatus.Should().Be("Connected");
        }

        [Fact]
        public void PeerCardInfo_RemoteCard_ShouldHaveCorrectProperties()
        {
            // Arrange & Act
            var peerCard = CreateTestPeerCardInfo("device-1", PeerCardType.Remote, "Connected", deviceName: "Test Device");

            // Assert
            peerCard.CardType.Should().Be(PeerCardType.Remote);
            peerCard.IsDittoServer.Should().BeFalse();
            peerCard.DisplayName.Should().Be("Test Device");
            peerCard.IsConnected.Should().BeTrue();
        }

        [Fact]
        public void PeerCardInfo_LocalCard_ShouldHaveCorrectProperties()
        {
            // Arrange & Act
            var peerCard = CreateTestPeerCardInfo("local-1", PeerCardType.Local, null, deviceName: "My Device");

            // Assert
            peerCard.CardType.Should().Be(PeerCardType.Local);
            peerCard.DisplayName.Should().Be("My Device");
        }

        [Fact]
        public void PeerCardInfo_IsConnected_WhenConnected_ShouldReturnTrue()
        {
            // Arrange & Act
            var peerCard = CreateTestPeerCardInfo("peer-1", PeerCardType.Remote, "Connected");

            // Assert
            peerCard.IsConnected.Should().BeTrue();
            peerCard.ConnectionStatus.Should().Be("Connected");
        }

        [Fact]
        public void PeerCardInfo_IsConnected_WhenNotConnected_ShouldReturnFalse()
        {
            // Arrange & Act
            var peerCard = CreateTestPeerCardInfo("peer-1", PeerCardType.Remote, "Disconnected");

            // Assert
            peerCard.IsConnected.Should().BeFalse();
            peerCard.ConnectionStatus.Should().Be("Not Connected");
        }

        [Fact]
        public void PeerCardInfo_LastUpdated_ShouldFormatCorrectly()
        {
            // Arrange
            var testDate = new DateTime(2023, 11, 14, 10, 30, 45, DateTimeKind.Utc);
            var peerCard = CreateTestPeerCardInfo("peer-1", PeerCardType.Remote, "Connected", lastUpdated: testDate);

            // Act
            var formatted = peerCard.LastUpdatedFormatted;

            // Assert
            formatted.Should().NotBeNullOrEmpty();
            peerCard.LastUpdated.Should().Be(testDate);
        }

        [Fact]
        public void PeerCardInfo_WithConnections_ShouldStoreActiveConnections()
        {
            // Arrange
            var connections = new List<PeerConnectionInfo>
            {
                new() { ConnectionType = "Bluetooth", ConnectionId = "bt-123", ApproximateDistanceInMeters = 5.0 },
                new() { ConnectionType = "WiFi", ConnectionId = "wifi-456", ApproximateDistanceInMeters = null }
            };

            var peerCard = CreateTestPeerCardInfo("peer-1", PeerCardType.Remote, "Connected", activeConnections: connections);

            // Assert
            peerCard.ActiveConnections.Should().NotBeNull();
            peerCard.ActiveConnections.Should().HaveCount(2);
            peerCard.ActiveConnections![0].ConnectionType.Should().Be("Bluetooth");
            peerCard.ActiveConnections[1].ConnectionType.Should().Be("WiFi");
        }

        [Fact]
        public void ObservablePeerCardInfo_UpdateFrom_ShouldUpdateProperties()
        {
            // Arrange
            var original = CreateTestPeerCardInfo("peer-1", PeerCardType.Remote, "Connected");
            var wrapper = new ObservablePeerCardInfo(original);

            var updated = CreateTestPeerCardInfo("peer-1", PeerCardType.Remote, "Disconnected", commitId: 9999);

            // Act
            wrapper.UpdateFrom(updated);

            // Assert
            wrapper.IsConnected.Should().BeFalse();
            wrapper.ConnectionStatus.Should().Be("Not Connected");
            wrapper.CommitId.Should().Be(9999);
        }

        [Fact]
        public void ObservablePeerCardInfo_UpdateFrom_WithDifferentId_ShouldThrow()
        {
            // Arrange
            var original = CreateTestPeerCardInfo("peer-1", PeerCardType.Remote, "Connected");
            var wrapper = new ObservablePeerCardInfo(original);

            var updated = CreateTestPeerCardInfo("peer-2", PeerCardType.Remote, "Connected");

            // Act & Assert
            var act = () => wrapper.UpdateFrom(updated);
            act.Should().Throw<InvalidOperationException>()
                .WithMessage("*Cannot change peer ID*");
        }

        #endregion

        #region Helper Methods

        /// <summary>
        /// Creates a test PeerCardInfo with the specified parameters
        /// </summary>
        private static PeerCardInfo CreateTestPeerCardInfo(
            string id,
            PeerCardType cardType,
            string? syncSessionStatus = null,
            string? deviceName = null,
            bool isDittoServer = false,
            long? commitId = null,
            DateTime? lastUpdated = null,
            List<PeerConnectionInfo>? activeConnections = null)
        {
            return new PeerCardInfo
            {
                Id = id,
                CardType = cardType,
                DeviceName = deviceName,
                IsDittoServer = isDittoServer,
                SyncSessionStatus = syncSessionStatus,
                CommitId = commitId ?? 12345,
                LastUpdated = lastUpdated ?? DateTime.UtcNow,
                ActiveConnections = activeConnections
            };
        }

        /// <summary>
        /// Creates a test ObservablePeerCardInfo wrapped around a PeerCardInfo
        /// </summary>
        private static ObservablePeerCardInfo CreateTestPeerCard(
            string id,
            PeerCardType cardType,
            string? syncSessionStatus = null,
            string? deviceName = null,
            bool isDittoServer = false,
            long? commitId = null,
            DateTime? lastUpdated = null,
            List<PeerConnectionInfo>? activeConnections = null)
        {
            var peerCardInfo = CreateTestPeerCardInfo(
                id,
                cardType,
                syncSessionStatus,
                deviceName,
                isDittoServer,
                commitId,
                lastUpdated,
                activeConnections);

            return new ObservablePeerCardInfo(peerCardInfo);
        }

        #endregion
    }
}
