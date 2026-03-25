using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Shared.Messages;
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;
using FluentAssertions;
using Moq;
using Xunit;

namespace EdgeStudioTests
{
    /// <summary>
    /// Unit tests for INavigationService interface and NavigationService implementation
    /// </summary>
    public class NavigationServiceTests : IDisposable
    {
        private readonly Mock<INavigationService> _mockNavigationService;
        private readonly NavigationService _realNavigationService;

        public NavigationServiceTests()
        {
            _mockNavigationService = new Mock<INavigationService>();
            _realNavigationService = new NavigationService();

            // Clean up messenger to ensure test isolation
            WeakReferenceMessenger.Default.Cleanup();
        }

        public void Dispose()
        {
            // Clean up messenger after each test
            WeakReferenceMessenger.Default.Cleanup();
        }

        #region Mock Interface Tests

        [Fact]
        public void MockNavigationService_NavigateTo_ShouldCallMethod()
        {
            // Arrange
            var navigationType = NavigationItemType.Query;
            _mockNavigationService.Setup(s => s.NavigateTo(It.IsAny<NavigationItemType>()));

            // Act
            _mockNavigationService.Object.NavigateTo(navigationType);

            // Assert
            _mockNavigationService.Verify(s => s.NavigateTo(NavigationItemType.Query), Times.Once);
        }

        [Fact]
        public void MockNavigationService_CurrentNavigationType_ShouldReturnValue()
        {
            // Arrange
            _mockNavigationService.Setup(s => s.CurrentNavigationType)
                .Returns(NavigationItemType.AppMetrics);

            // Act
            var result = _mockNavigationService.Object.CurrentNavigationType;

            // Assert
            result.Should().Be(NavigationItemType.AppMetrics);
        }

        [Fact]
        public void MockNavigationService_NavigateTo_AllNavigationTypes_ShouldSucceed()
        {
            // Arrange
            var navigationTypes = new[]
            {
                NavigationItemType.Subscriptions,
                NavigationItemType.Query,
                NavigationItemType.Observers,
                NavigationItemType.AppMetrics
            };

            _mockNavigationService.Setup(s => s.NavigateTo(It.IsAny<NavigationItemType>()));

            // Act & Assert
            foreach (var type in navigationTypes)
            {
                var act = () => _mockNavigationService.Object.NavigateTo(type);
                act.Should().NotThrow();
                _mockNavigationService.Verify(s => s.NavigateTo(type), Times.Once);
            }
        }

        #endregion

        #region Real Implementation Tests - Initial State

        [Fact]
        public void NavigationService_InitialState_ShouldBeSubscriptions()
        {
            // Arrange & Act
            var service = new NavigationService();

            // Assert
            service.CurrentNavigationType.Should().Be(NavigationItemType.Subscriptions);
        }

        #endregion

        #region Real Implementation Tests - NavigateTo

        [Fact]
        public void NavigationService_NavigateTo_Query_ShouldUpdateCurrentNavigationType()
        {
            // Arrange
            var service = new NavigationService();

            // Act
            service.NavigateTo(NavigationItemType.Query);

            // Assert
            service.CurrentNavigationType.Should().Be(NavigationItemType.Query);
        }

        [Fact]
        public void NavigationService_NavigateTo_Observers_ShouldUpdateCurrentNavigationType()
        {
            // Arrange
            var service = new NavigationService();

            // Act
            service.NavigateTo(NavigationItemType.Observers);

            // Assert
            service.CurrentNavigationType.Should().Be(NavigationItemType.Observers);
        }

        [Fact]
        public void NavigationService_NavigateTo_Tools_ShouldUpdateCurrentNavigationType()
        {
            // Arrange
            var service = new NavigationService();

            // Act
            service.NavigateTo(NavigationItemType.AppMetrics);

            // Assert
            service.CurrentNavigationType.Should().Be(NavigationItemType.AppMetrics);
        }

        [Fact]
        public void NavigationService_NavigateTo_Subscriptions_ShouldUpdateCurrentNavigationType()
        {
            // Arrange
            var service = new NavigationService();
            service.NavigateTo(NavigationItemType.Query); // Navigate away first

            // Act
            service.NavigateTo(NavigationItemType.Subscriptions);

            // Assert
            service.CurrentNavigationType.Should().Be(NavigationItemType.Subscriptions);
        }

        [Fact]
        public void NavigationService_NavigateTo_AllTypes_ShouldUpdateSequentially()
        {
            // Arrange
            var service = new NavigationService();
            var navigationSequence = new[]
            {
                NavigationItemType.Query,
                NavigationItemType.Observers,
                NavigationItemType.AppMetrics,
                NavigationItemType.Subscriptions
            };

            // Act & Assert
            foreach (var type in navigationSequence)
            {
                service.NavigateTo(type);
                service.CurrentNavigationType.Should().Be(type);
            }
        }

        #endregion

        #region Real Implementation Tests - Messaging

        [Fact]
        public void NavigationService_NavigateTo_ShouldSendNavigationChangedMessage()
        {
            // Arrange
            var service = new NavigationService();
            NavigationChangedMessage? receivedMessage = null;

            WeakReferenceMessenger.Default.Register<NavigationChangedMessage>(this, (r, m) =>
            {
                receivedMessage = m;
            });

            // Act
            service.NavigateTo(NavigationItemType.Query);

            // Assert
            receivedMessage.Should().NotBeNull();
            receivedMessage!.NavigationType.Should().Be(NavigationItemType.Query);

            // Cleanup
            WeakReferenceMessenger.Default.Unregister<NavigationChangedMessage>(this);
        }

        [Fact]
        public void NavigationService_NavigateTo_DifferentTypes_ShouldSendMultipleMessages()
        {
            // Arrange
            var service = new NavigationService();
            var receivedMessages = new List<NavigationChangedMessage>();

            WeakReferenceMessenger.Default.Register<NavigationChangedMessage>(this, (r, m) =>
            {
                receivedMessages.Add(m);
            });

            // Act
            service.NavigateTo(NavigationItemType.Query);
            service.NavigateTo(NavigationItemType.Observers);
            service.NavigateTo(NavigationItemType.AppMetrics);

            // Assert
            receivedMessages.Should().HaveCount(3);
            receivedMessages[0].NavigationType.Should().Be(NavigationItemType.Query);
            receivedMessages[1].NavigationType.Should().Be(NavigationItemType.Observers);
            receivedMessages[2].NavigationType.Should().Be(NavigationItemType.AppMetrics);

            // Cleanup
            WeakReferenceMessenger.Default.Unregister<NavigationChangedMessage>(this);
        }

        [Fact]
        public void NavigationService_NavigateTo_SameType_ShouldNotSendMessage()
        {
            // Arrange
            var service = new NavigationService();
            var messageCount = 0;

            WeakReferenceMessenger.Default.Register<NavigationChangedMessage>(this, (r, m) =>
            {
                messageCount++;
            });

            // Act
            service.NavigateTo(NavigationItemType.Subscriptions); // Navigate to same type as initial
            service.NavigateTo(NavigationItemType.Subscriptions); // Navigate to same type again

            // Assert
            messageCount.Should().Be(0, "navigating to the same type should not send messages");

            // Cleanup
            WeakReferenceMessenger.Default.Unregister<NavigationChangedMessage>(this);
        }

        [Fact]
        public void NavigationService_NavigateTo_SameTypeTwice_AfterChanging_ShouldSendOnlyOneMessage()
        {
            // Arrange
            var service = new NavigationService();
            var receivedMessages = new List<NavigationChangedMessage>();

            WeakReferenceMessenger.Default.Register<NavigationChangedMessage>(this, (r, m) =>
            {
                receivedMessages.Add(m);
            });

            // Act
            service.NavigateTo(NavigationItemType.Query); // Change to Query
            service.NavigateTo(NavigationItemType.Query); // Try to navigate to Query again

            // Assert
            receivedMessages.Should().HaveCount(1, "second navigation to same type should not send message");
            receivedMessages[0].NavigationType.Should().Be(NavigationItemType.Query);

            // Cleanup
            WeakReferenceMessenger.Default.Unregister<NavigationChangedMessage>(this);
        }

        [Fact]
        public void NavigationService_NavigateTo_MessageContent_ShouldMatchNavigationType()
        {
            // Arrange
            var service = new NavigationService();
            var targetType = NavigationItemType.AppMetrics;
            NavigationChangedMessage? receivedMessage = null;

            WeakReferenceMessenger.Default.Register<NavigationChangedMessage>(this, (r, m) =>
            {
                receivedMessage = m;
            });

            // Act
            service.NavigateTo(targetType);

            // Assert
            receivedMessage.Should().NotBeNull();
            receivedMessage!.NavigationType.Should().Be(targetType);
            service.CurrentNavigationType.Should().Be(targetType);

            // Cleanup
            WeakReferenceMessenger.Default.Unregister<NavigationChangedMessage>(this);
        }

        #endregion

        #region Real Implementation Tests - Multiple Subscribers

        [Fact]
        public void NavigationService_NavigateTo_MultipleSubscribers_ShouldNotifyAll()
        {
            // Arrange
            var service = new NavigationService();
            var receivedMessages = new List<NavigationChangedMessage>();

            // Create multiple recipients
            var recipient1 = new TestRecipient();
            var recipient2 = new TestRecipient();
            var recipient3 = new TestRecipient();

            WeakReferenceMessenger.Default.Register<NavigationChangedMessage>(recipient1, (r, m) =>
            {
                receivedMessages.Add(m);
            });

            WeakReferenceMessenger.Default.Register<NavigationChangedMessage>(recipient2, (r, m) =>
            {
                receivedMessages.Add(m);
            });

            WeakReferenceMessenger.Default.Register<NavigationChangedMessage>(recipient3, (r, m) =>
            {
                receivedMessages.Add(m);
            });

            // Act
            service.NavigateTo(NavigationItemType.Observers);

            // Assert
            receivedMessages.Should().HaveCount(3, "all three subscribers should receive the message");
            receivedMessages.Should().OnlyContain(m => m.NavigationType == NavigationItemType.Observers);

            // Cleanup
            WeakReferenceMessenger.Default.Unregister<NavigationChangedMessage>(recipient1);
            WeakReferenceMessenger.Default.Unregister<NavigationChangedMessage>(recipient2);
            WeakReferenceMessenger.Default.Unregister<NavigationChangedMessage>(recipient3);
        }

        #endregion

        #region Real Implementation Tests - Edge Cases

        [Fact]
        public void NavigationService_MultipleInstances_ShouldBeIndependent()
        {
            // Arrange
            var service1 = new NavigationService();
            var service2 = new NavigationService();

            // Act
            service1.NavigateTo(NavigationItemType.Query);
            service2.NavigateTo(NavigationItemType.AppMetrics);

            // Assert
            service1.CurrentNavigationType.Should().Be(NavigationItemType.Query);
            service2.CurrentNavigationType.Should().Be(NavigationItemType.AppMetrics);
            service1.CurrentNavigationType.Should().NotBe(service2.CurrentNavigationType);
        }

        [Fact]
        public void NavigationService_RapidNavigation_ShouldHandleAllChanges()
        {
            // Arrange
            var service = new NavigationService();
            var messageCount = 0;

            WeakReferenceMessenger.Default.Register<NavigationChangedMessage>(this, (r, m) =>
            {
                messageCount++;
            });

            // Act - Rapidly navigate between different types
            service.NavigateTo(NavigationItemType.Query);
            service.NavigateTo(NavigationItemType.Observers);
            service.NavigateTo(NavigationItemType.AppMetrics);
            service.NavigateTo(NavigationItemType.Subscriptions);
            service.NavigateTo(NavigationItemType.Query);

            // Assert
            messageCount.Should().Be(5);
            service.CurrentNavigationType.Should().Be(NavigationItemType.Query);

            // Cleanup
            WeakReferenceMessenger.Default.Unregister<NavigationChangedMessage>(this);
        }

        [Fact]
        public void NavigationService_NavigationSequence_ShouldMaintainCorrectState()
        {
            // Arrange
            var service = new NavigationService();
            var states = new List<NavigationItemType>();

            WeakReferenceMessenger.Default.Register<NavigationChangedMessage>(this, (r, m) =>
            {
                states.Add(service.CurrentNavigationType);
            });

            // Act
            var expectedSequence = new[]
            {
                NavigationItemType.Query,
                NavigationItemType.AppMetrics,
                NavigationItemType.Observers
            };

            foreach (var type in expectedSequence)
            {
                service.NavigateTo(type);
            }

            // Assert
            states.Should().Equal(expectedSequence);

            // Cleanup
            WeakReferenceMessenger.Default.Unregister<NavigationChangedMessage>(this);
        }

        #endregion

        #region NavigationItemType Enum Tests

        [Fact]
        public void NavigationItemType_AllValues_ShouldBeSupported()
        {
            // Arrange
            var service = new NavigationService();
            var allTypes = Enum.GetValues<NavigationItemType>();

            // Act & Assert
            foreach (var type in allTypes)
            {
                var act = () => service.NavigateTo(type);
                act.Should().NotThrow($"navigation to {type} should be supported");
                service.CurrentNavigationType.Should().Be(type);
            }
        }

        [Fact]
        public void NavigationItemType_Values_ShouldMatchExpectedCount()
        {
            // Arrange & Act
            var allTypes = Enum.GetValues<NavigationItemType>();

            // Assert
            allTypes.Should().HaveCount(6, "there should be exactly 6 navigation types");
            allTypes.Should().Contain(NavigationItemType.Subscriptions);
            allTypes.Should().Contain(NavigationItemType.Query);
            allTypes.Should().Contain(NavigationItemType.Observers);
            allTypes.Should().Contain(NavigationItemType.Logging);
            allTypes.Should().Contain(NavigationItemType.AppMetrics);
            allTypes.Should().Contain(NavigationItemType.QueryMetrics);
        }

        #endregion
    }

    /// <summary>
    /// Helper class for testing multiple message recipients
    /// </summary>
    internal class TestRecipient
    {
    }
}
