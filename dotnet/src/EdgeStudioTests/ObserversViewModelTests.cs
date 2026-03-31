using EdgeStudio.Shared.Data.Repositories;
using EdgeStudio.Shared.Models;
using EdgeStudio.ViewModels;
using FluentAssertions;
using Moq;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Xunit;

namespace EdgeStudioTests
{
    /// <summary>
    /// Unit tests for ObserversViewModel
    /// </summary>
    public class ObserversViewModelTests
    {
        private readonly Mock<IObserverRepository> _mockRepository;
        private readonly ObserversViewModel _viewModel;

        public ObserversViewModelTests()
        {
            _mockRepository = new Mock<IObserverRepository>();
            _viewModel = new ObserversViewModel(_mockRepository.Object);
        }

        #region Initial State Tests

        [Fact]
        public void Constructor_ShouldInitializeWithEmptyCollections()
        {
            _viewModel.Items.Should().BeEmpty();
            _viewModel.Events.Should().BeEmpty();
            _viewModel.FilteredEventData.Should().BeEmpty();
        }

        [Fact]
        public void Constructor_ShouldInitializeWithCorrectTitles()
        {
            _viewModel.ListingTitle.Should().Be("OBSERVERS");
            _viewModel.DetailsTitle.Should().Be("OBSERVER EVENTS");
        }

        [Fact]
        public void Constructor_ShouldHaveDefaultFilterMode()
        {
            _viewModel.EventFilterMode.Should().Be("items");
        }

        [Fact]
        public void HasItems_WhenEmpty_ShouldBeFalse()
        {
            _viewModel.HasItems.Should().BeFalse();
        }

        [Fact]
        public void ShowEmptyState_WhenEmptyAndNotLoading_ShouldBeTrue()
        {
            _viewModel.ShowEmptyState.Should().BeTrue();
        }

        [Fact]
        public void HasSelectedObserver_WhenNull_ShouldBeFalse()
        {
            _viewModel.HasSelectedObserver.Should().BeFalse();
        }

        [Fact]
        public void HasSelectedEvent_WhenNull_ShouldBeFalse()
        {
            _viewModel.HasSelectedEvent.Should().BeFalse();
        }

        #endregion

        #region LoadAsync Tests

        [Fact]
        public async Task LoadAsync_ShouldPopulateItems()
        {
            // Arrange
            var observers = new List<DittoDatabaseObserver>
            {
                new("obs-1", "Observer 1", "SELECT * FROM users"),
                new("obs-2", "Observer 2", "SELECT * FROM tasks")
            };
            _mockRepository.Setup(r => r.GetObserversAsync())
                .ReturnsAsync(observers);

            // Act
            await _viewModel.LoadAsync();

            // Assert
            _viewModel.Items.Should().HaveCount(2);
            _viewModel.HasItems.Should().BeTrue();
            _viewModel.ShowEmptyState.Should().BeFalse();
        }

        [Fact]
        public async Task LoadAsync_WhenEmpty_ShouldShowEmptyState()
        {
            // Arrange
            _mockRepository.Setup(r => r.GetObserversAsync())
                .ReturnsAsync(new List<DittoDatabaseObserver>());

            // Act
            await _viewModel.LoadAsync();

            // Assert
            _viewModel.Items.Should().BeEmpty();
            _viewModel.ShowEmptyState.Should().BeTrue();
        }

        #endregion

        #region SaveObserverAsync Tests

        [Fact]
        public async Task SaveObserverAsync_WithValidForm_ShouldAddToItems()
        {
            // Arrange
            _mockRepository.Setup(r => r.GetObserversAsync())
                .ReturnsAsync(new List<DittoDatabaseObserver>());
            await _viewModel.LoadAsync();

            _viewModel.ObserverFormModel.Name = "New Observer";
            _viewModel.ObserverFormModel.Query = "SELECT * FROM products";
            _mockRepository.Setup(r => r.SaveObserverAsync(It.IsAny<DittoDatabaseObserver>()))
                .Returns(Task.CompletedTask);

            // Act
            _viewModel.SaveObserverCommand.Execute(null);
            // Give async operation time to complete
            await Task.Delay(100);

            // Assert
            _viewModel.Items.Should().HaveCount(1);
            _viewModel.Items[0].Name.Should().Be("New Observer");
        }

        [Fact]
        public async Task SaveObserverAsync_WithInvalidForm_ShouldNotAddToItems()
        {
            // Arrange
            _viewModel.ObserverFormModel.Name = "";
            _viewModel.ObserverFormModel.Query = "";

            // Act
            _viewModel.SaveObserverCommand.Execute(null);
            await Task.Delay(100);

            // Assert
            _viewModel.Items.Should().BeEmpty();
            _mockRepository.Verify(r => r.SaveObserverAsync(It.IsAny<DittoDatabaseObserver>()), Times.Never);
        }

        #endregion

        #region DeleteObserverAsync Tests

        [Fact]
        public async Task DeleteObserverAsync_ShouldRemoveFromItems()
        {
            // Arrange
            var observer = new DittoDatabaseObserver("obs-1", "Test Observer", "SELECT * FROM users");
            _mockRepository.Setup(r => r.GetObserversAsync())
                .ReturnsAsync(new List<DittoDatabaseObserver> { observer });
            _mockRepository.Setup(r => r.DeleteObserverAsync("obs-1"))
                .Returns(Task.CompletedTask);
            await _viewModel.LoadAsync();

            // Act
            _viewModel.DeleteObserverCommand.Execute(observer);
            await Task.Delay(100);

            // Assert
            _viewModel.Items.Should().BeEmpty();
        }

        [Fact]
        public async Task DeleteObserverAsync_WithNull_ShouldNotCallRepository()
        {
            // Act
            _viewModel.DeleteObserverCommand.Execute(null);
            await Task.Delay(50);

            // Assert
            _mockRepository.Verify(r => r.DeleteObserverAsync(It.IsAny<string>()), Times.Never);
        }

        #endregion

        #region Observer Form Model Tests

        [Fact]
        public void AddObserver_ShouldResetFormModel()
        {
            // Arrange
            _viewModel.ObserverFormModel.Name = "Previous";
            _viewModel.ObserverFormModel.Query = "Previous Query";

            // Act
            _viewModel.AddObserverCommand.Execute(null);

            // Assert
            _viewModel.ObserverFormModel.Name.Should().BeEmpty();
            _viewModel.ObserverFormModel.Query.Should().BeEmpty();
        }

        [Fact]
        public void EditObserver_ShouldPopulateFormModel()
        {
            // Arrange
            var observer = new DittoDatabaseObserver("obs-1", "Test Observer", "SELECT * FROM users");

            // Act
            _viewModel.EditObserverCommand.Execute(observer);

            // Assert
            _viewModel.ObserverFormModel.Name.Should().Be("Test Observer");
            _viewModel.ObserverFormModel.Query.Should().Be("SELECT * FROM users");
        }

        #endregion

        #region SelectEvent and Filter Tests

        [Fact]
        public void SelectEvent_ShouldUpdateSelectedEvent()
        {
            // Arrange
            var evt = new ObserverEvent
            {
                ObserverId = "obs-1",
                Data = new List<string> { "{\"a\":1}", "{\"b\":2}" },
                InsertIndexes = new List<int> { 0 },
                UpdatedIndexes = new List<int> { 1 }
            };

            // Act
            _viewModel.SelectEventCommand.Execute(evt);

            // Assert
            _viewModel.SelectedEvent.Should().Be(evt);
            _viewModel.HasSelectedEvent.Should().BeTrue();
            _viewModel.FilteredEventData.Should().HaveCount(2); // default "items" mode
        }

        [Fact]
        public void SetEventFilter_ToInserted_ShouldFilterData()
        {
            // Arrange
            var evt = new ObserverEvent
            {
                ObserverId = "obs-1",
                Data = new List<string> { "{\"a\":1}", "{\"b\":2}", "{\"c\":3}" },
                InsertIndexes = new List<int> { 0 },
                UpdatedIndexes = new List<int> { 2 }
            };
            _viewModel.SelectEventCommand.Execute(evt);

            // Act
            _viewModel.SetEventFilterCommand.Execute("inserted");

            // Assert
            _viewModel.FilteredEventData.Should().HaveCount(1);
            _viewModel.FilteredEventData[0].Should().Be("{\"a\":1}");
        }

        [Fact]
        public void SetEventFilter_ToUpdated_ShouldFilterData()
        {
            // Arrange
            var evt = new ObserverEvent
            {
                ObserverId = "obs-1",
                Data = new List<string> { "{\"a\":1}", "{\"b\":2}", "{\"c\":3}" },
                InsertIndexes = new List<int> { 0 },
                UpdatedIndexes = new List<int> { 2 }
            };
            _viewModel.SelectEventCommand.Execute(evt);

            // Act
            _viewModel.SetEventFilterCommand.Execute("updated");

            // Assert
            _viewModel.FilteredEventData.Should().HaveCount(1);
            _viewModel.FilteredEventData[0].Should().Be("{\"c\":3}");
        }

        [Fact]
        public void SetEventFilter_ToItems_ShouldReturnAllData()
        {
            // Arrange
            var evt = new ObserverEvent
            {
                ObserverId = "obs-1",
                Data = new List<string> { "{\"a\":1}", "{\"b\":2}", "{\"c\":3}" },
                InsertIndexes = new List<int> { 0 },
                UpdatedIndexes = new List<int> { 2 }
            };
            _viewModel.SelectEventCommand.Execute(evt);
            _viewModel.SetEventFilterCommand.Execute("inserted"); // change first

            // Act
            _viewModel.SetEventFilterCommand.Execute("items");

            // Assert
            _viewModel.FilteredEventData.Should().HaveCount(3);
        }

        [Fact]
        public void SelectedEvent_WhenChanged_RefreshesFilteredEventData()
        {
            var mockRepo = new Mock<IObserverRepository>();
            var vm = new ObserversViewModel(mockRepo.Object);
            var testEvent = new ObserverEvent
            {
                ObserverId = "obs1",
                Data = new List<string> { "{\"_id\":\"1\",\"name\":\"test\"}", "{\"_id\":\"2\",\"name\":\"test2\"}" },
                InsertIndexes = new List<int> { 0 },
                UpdatedIndexes = new List<int> { 1 },
                EventTime = DateTime.Now
            };

            vm.SelectedEvent = testEvent;

            vm.FilteredEventData.Should().HaveCount(2);
            vm.HasSelectedEvent.Should().BeTrue();
        }

        [Fact]
        public void SelectedEvent_WithInsertedFilter_ShowsOnlyInsertedData()
        {
            var mockRepo = new Mock<IObserverRepository>();
            var vm = new ObserversViewModel(mockRepo.Object);
            vm.EventFilterMode = "inserted";
            var testEvent = new ObserverEvent
            {
                ObserverId = "obs1",
                Data = new List<string> { "{\"_id\":\"1\"}", "{\"_id\":\"2\"}", "{\"_id\":\"3\"}" },
                InsertIndexes = new List<int> { 0, 2 },
                UpdatedIndexes = new List<int> { 1 },
                EventTime = DateTime.Now
            };

            vm.SelectedEvent = testEvent;

            vm.FilteredEventData.Should().HaveCount(2);
            vm.FilteredEventData[0].Should().Be("{\"_id\":\"1\"}");
            vm.FilteredEventData[1].Should().Be("{\"_id\":\"3\"}");
        }

        #endregion

        #region DetailViewMode Tests

        [Fact]
        public void SetDetailViewMode_ChangesMode()
        {
            var mockRepo = new Mock<IObserverRepository>();
            var vm = new ObserversViewModel(mockRepo.Object);

            vm.SetDetailViewModeCommand.Execute("table");

            vm.DetailViewMode.Should().Be("table");
            vm.IsTableMode.Should().BeTrue();
            vm.IsRawMode.Should().BeFalse();
        }

        [Fact]
        public void SetDetailViewMode_DefaultIsRaw()
        {
            var mockRepo = new Mock<IObserverRepository>();
            var vm = new ObserversViewModel(mockRepo.Object);

            vm.DetailViewMode.Should().Be("raw");
            vm.IsRawMode.Should().BeTrue();
            vm.IsTableMode.Should().BeFalse();
        }

        [Fact]
        public void SetDetailViewMode_TogglesBackToRaw()
        {
            var mockRepo = new Mock<IObserverRepository>();
            var vm = new ObserversViewModel(mockRepo.Object);

            vm.SetDetailViewModeCommand.Execute("table");
            vm.IsTableMode.Should().BeTrue();

            vm.SetDetailViewModeCommand.Execute("raw");
            vm.IsRawMode.Should().BeTrue();
            vm.IsTableMode.Should().BeFalse();
        }

        #endregion

        #region FilterModeIndicator Tests

        [Fact]
        public void FilterModeIndicators_ReflectCurrentFilter()
        {
            var mockRepo = new Mock<IObserverRepository>();
            var vm = new ObserversViewModel(mockRepo.Object);

            // Default is "items"
            vm.IsFilterItems.Should().BeTrue();
            vm.IsFilterInserted.Should().BeFalse();
            vm.IsFilterUpdated.Should().BeFalse();

            vm.EventFilterMode = "inserted";
            vm.IsFilterItems.Should().BeFalse();
            vm.IsFilterInserted.Should().BeTrue();
            vm.IsFilterUpdated.Should().BeFalse();

            vm.EventFilterMode = "updated";
            vm.IsFilterUpdated.Should().BeTrue();
            vm.IsFilterInserted.Should().BeFalse();
            vm.IsFilterItems.Should().BeFalse();
        }

        [Fact]
        public void FilterModeIndicators_BackToItems()
        {
            var mockRepo = new Mock<IObserverRepository>();
            var vm = new ObserversViewModel(mockRepo.Object);

            vm.EventFilterMode = "updated";
            vm.IsFilterUpdated.Should().BeTrue();

            vm.EventFilterMode = "items";
            vm.IsFilterItems.Should().BeTrue();
            vm.IsFilterUpdated.Should().BeFalse();
        }

        #endregion

        #region Pagination Tests

        [Fact]
        public void EventPagination_PageCountCalculation()
        {
            var mockRepo = new Mock<IObserverRepository>();
            var vm = new ObserversViewModel(mockRepo.Object);
            // EventPageSize defaults to 25, so with 0 events, page count should be 1
            vm.EventPageCount.Should().Be(1);
        }

        [Fact]
        public void DetailPagination_PagedFilteredDataRespectPageSize()
        {
            var mockRepo = new Mock<IObserverRepository>();
            var vm = new ObserversViewModel(mockRepo.Object);
            vm.DetailPageSize = 2;
            var testEvent = new ObserverEvent
            {
                ObserverId = "obs1",
                Data = new List<string> { "a", "b", "c", "d", "e" },
                EventTime = DateTime.Now
            };
            vm.SelectedEvent = testEvent;

            // First page should have 2 items
            vm.PagedFilteredEventData.Should().HaveCount(2);
            vm.PagedFilteredEventData[0].Should().Be("a");
            vm.PagedFilteredEventData[1].Should().Be("b");
            vm.DetailPageCount.Should().Be(3); // ceil(5/2)
        }

        [Fact]
        public void DetailPagination_NextPageShowsNextItems()
        {
            var mockRepo = new Mock<IObserverRepository>();
            var vm = new ObserversViewModel(mockRepo.Object);
            vm.DetailPageSize = 2;
            var testEvent = new ObserverEvent
            {
                ObserverId = "obs1",
                Data = new List<string> { "a", "b", "c", "d", "e" },
                EventTime = DateTime.Now
            };
            vm.SelectedEvent = testEvent;
            vm.DetailNextPageCommand.Execute(null);

            vm.DetailCurrentPage.Should().Be(2);
            vm.PagedFilteredEventData.Should().HaveCount(2);
            vm.PagedFilteredEventData[0].Should().Be("c");
            vm.PagedFilteredEventData[1].Should().Be("d");
        }

        [Fact]
        public void DetailPagination_LastPageShowsRemainingItems()
        {
            var mockRepo = new Mock<IObserverRepository>();
            var vm = new ObserversViewModel(mockRepo.Object);
            vm.DetailPageSize = 2;
            var testEvent = new ObserverEvent
            {
                ObserverId = "obs1",
                Data = new List<string> { "a", "b", "c", "d", "e" },
                EventTime = DateTime.Now
            };
            vm.SelectedEvent = testEvent;
            vm.DetailNextPageCommand.Execute(null); // page 2
            vm.DetailNextPageCommand.Execute(null); // page 3

            vm.DetailCurrentPage.Should().Be(3);
            vm.PagedFilteredEventData.Should().HaveCount(1);
            vm.PagedFilteredEventData[0].Should().Be("e");
        }

        [Fact]
        public void DetailPagination_PreviousPageAtFirstPageStaysAtFirst()
        {
            var mockRepo = new Mock<IObserverRepository>();
            var vm = new ObserversViewModel(mockRepo.Object);
            vm.DetailPageSize = 2;
            var testEvent = new ObserverEvent
            {
                ObserverId = "obs1",
                Data = new List<string> { "a", "b", "c" },
                EventTime = DateTime.Now
            };
            vm.SelectedEvent = testEvent;
            vm.DetailPreviousPageCommand.Execute(null);

            vm.DetailCurrentPage.Should().Be(1);
            vm.PagedFilteredEventData[0].Should().Be("a");
        }

        [Fact]
        public void EventPagination_NextPageBeyondLastStaysAtLast()
        {
            var mockRepo = new Mock<IObserverRepository>();
            var vm = new ObserversViewModel(mockRepo.Object);
            // No events, so page count is 1
            vm.EventNextPageCommand.Execute(null);
            vm.EventCurrentPage.Should().Be(1);
        }

        [Fact]
        public void DetailPagination_ChangingFilterResetsToFirstPage()
        {
            var mockRepo = new Mock<IObserverRepository>();
            var vm = new ObserversViewModel(mockRepo.Object);
            vm.DetailPageSize = 2;
            var testEvent = new ObserverEvent
            {
                ObserverId = "obs1",
                Data = new List<string> { "a", "b", "c", "d", "e" },
                InsertIndexes = new List<int> { 0, 1, 2 },
                UpdatedIndexes = new List<int> { 3, 4 },
                EventTime = DateTime.Now
            };
            vm.SelectedEvent = testEvent;
            vm.DetailNextPageCommand.Execute(null); // page 2
            vm.DetailCurrentPage.Should().Be(2);

            // Changing filter should reset to page 1
            vm.SetEventFilterCommand.Execute("inserted");
            vm.DetailCurrentPage.Should().Be(1);
        }

        #endregion

        #region DeactivateObserver Tests

        [Fact]
        public async Task DeactivateObserver_ShouldCallRepository()
        {
            // Arrange
            var observer = new DittoDatabaseObserver("obs-1", "Test", "SELECT * FROM users")
            {
                IsActive = true
            };
            _mockRepository.Setup(r => r.GetObserversAsync())
                .ReturnsAsync(new List<DittoDatabaseObserver> { observer });
            await _viewModel.LoadAsync();

            // Act
            _viewModel.DeactivateObserverCommand.Execute(observer);

            // Assert
            _mockRepository.Verify(r => r.DeactivateObserver("obs-1"), Times.Once);
        }

        #endregion
    }
}
