using EdgeStudio.Shared.Models;
using FluentAssertions;
using System;
using System.Collections.Generic;
using Xunit;

namespace EdgeStudioTests
{
    /// <summary>
    /// Unit tests for DittoDatabaseObserver, ObserverEvent, and ObserverFormModel
    /// </summary>
    public class ObserverModelTests
    {
        #region DittoDatabaseObserver Tests

        [Fact]
        public void DittoDatabaseObserver_ShouldCreateWithCorrectProperties()
        {
            var observer = new DittoDatabaseObserver("id-1", "Test Observer", "SELECT * FROM users");

            observer.Id.Should().Be("id-1");
            observer.Name.Should().Be("Test Observer");
            observer.Query.Should().Be("SELECT * FROM users");
            observer.IsActive.Should().BeFalse();
        }

        [Fact]
        public void DittoDatabaseObserver_WithIsActive_ShouldSetCorrectly()
        {
            var observer = new DittoDatabaseObserver("id-1", "Test", "SELECT * FROM test")
            {
                IsActive = true
            };

            observer.IsActive.Should().BeTrue();
        }

        [Fact]
        public void DittoDatabaseObserver_Implements_IIdModel()
        {
            var observer = new DittoDatabaseObserver("id-1", "Test", "SELECT * FROM test");

            observer.Should().BeAssignableTo<IIdModel>();
        }

        [Fact]
        public void DittoDatabaseObserver_WithRecord_ShouldSupportEquality()
        {
            var observer1 = new DittoDatabaseObserver("id-1", "Test", "SELECT * FROM test");
            var observer2 = new DittoDatabaseObserver("id-1", "Test", "SELECT * FROM test");

            observer1.Should().Be(observer2);
        }

        [Fact]
        public void DittoDatabaseObserver_WithRecord_ShouldSupportWith()
        {
            var observer = new DittoDatabaseObserver("id-1", "Test", "SELECT * FROM test");
            var activated = observer with { IsActive = true };

            activated.IsActive.Should().BeTrue();
            activated.Id.Should().Be("id-1");
            activated.Name.Should().Be("Test");
        }

        #endregion

        #region ObserverEvent Tests

        [Fact]
        public void ObserverEvent_ShouldCreateWithDefaults()
        {
            var evt = new ObserverEvent();

            evt.Id.Should().NotBeNullOrEmpty();
            evt.ObserverId.Should().BeEmpty();
            evt.Data.Should().BeEmpty();
            evt.InsertIndexes.Should().BeEmpty();
            evt.UpdatedIndexes.Should().BeEmpty();
            evt.DeletedIndexes.Should().BeEmpty();
            evt.MovedIndexes.Should().BeEmpty();
        }

        [Fact]
        public void ObserverEvent_GetInsertedData_ShouldReturnCorrectItems()
        {
            var evt = new ObserverEvent
            {
                Data = new List<string> { "{\"a\":1}", "{\"b\":2}", "{\"c\":3}" },
                InsertIndexes = new List<int> { 0, 2 }
            };

            var result = evt.GetInsertedData();

            result.Should().HaveCount(2);
            result[0].Should().Be("{\"a\":1}");
            result[1].Should().Be("{\"c\":3}");
        }

        [Fact]
        public void ObserverEvent_GetUpdatedData_ShouldReturnCorrectItems()
        {
            var evt = new ObserverEvent
            {
                Data = new List<string> { "{\"a\":1}", "{\"b\":2}", "{\"c\":3}" },
                UpdatedIndexes = new List<int> { 1 }
            };

            var result = evt.GetUpdatedData();

            result.Should().HaveCount(1);
            result[0].Should().Be("{\"b\":2}");
        }

        [Fact]
        public void ObserverEvent_GetInsertedData_WithEmptyData_ShouldReturnEmpty()
        {
            var evt = new ObserverEvent
            {
                Data = new List<string>(),
                InsertIndexes = new List<int> { 0, 1 }
            };

            evt.GetInsertedData().Should().BeEmpty();
        }

        [Fact]
        public void ObserverEvent_GetInsertedData_WithEmptyIndexes_ShouldReturnEmpty()
        {
            var evt = new ObserverEvent
            {
                Data = new List<string> { "{\"a\":1}" },
                InsertIndexes = new List<int>()
            };

            evt.GetInsertedData().Should().BeEmpty();
        }

        [Fact]
        public void ObserverEvent_GetInsertedData_WithOutOfBoundsIndex_ShouldSkipInvalid()
        {
            var evt = new ObserverEvent
            {
                Data = new List<string> { "{\"a\":1}" },
                InsertIndexes = new List<int> { 0, 5 }
            };

            var result = evt.GetInsertedData();
            result.Should().HaveCount(1);
            result[0].Should().Be("{\"a\":1}");
        }

        [Fact]
        public void ObserverEvent_FormattedEventTime_ShouldFormatCorrectly()
        {
            var specificTime = new DateTime(2026, 3, 31, 14, 30, 45, 123);
            var evt = new ObserverEvent { EventTime = specificTime };

            evt.FormattedEventTime.Should().Be("14:30:45.123");
        }

        #endregion

        #region ObserverFormModel Tests

        [Fact]
        public void ObserverFormModel_Reset_ShouldClearAllFields()
        {
            var form = new ObserverFormModel
            {
                Name = "Test",
                Query = "SELECT * FROM test"
            };

            form.Reset();

            form.Name.Should().BeEmpty();
            form.Query.Should().BeEmpty();
        }

        [Fact]
        public void ObserverFormModel_IsValid_WithNameAndQuery_ShouldReturnTrue()
        {
            var form = new ObserverFormModel
            {
                Name = "Test Observer",
                Query = "SELECT * FROM users"
            };

            form.IsValid().Should().BeTrue();
        }

        [Fact]
        public void ObserverFormModel_IsValid_WithEmptyName_ShouldReturnFalse()
        {
            var form = new ObserverFormModel
            {
                Name = "",
                Query = "SELECT * FROM users"
            };

            form.IsValid().Should().BeFalse();
        }

        [Fact]
        public void ObserverFormModel_IsValid_WithEmptyQuery_ShouldReturnFalse()
        {
            var form = new ObserverFormModel
            {
                Name = "Test",
                Query = ""
            };

            form.IsValid().Should().BeFalse();
        }

        [Fact]
        public void ObserverFormModel_GetValidationError_WithEmptyName_ShouldReturnNameError()
        {
            var form = new ObserverFormModel { Name = "", Query = "SELECT * FROM users" };

            form.GetValidationError().Should().Contain("name");
        }

        [Fact]
        public void ObserverFormModel_GetValidationError_WithEmptyQuery_ShouldReturnQueryError()
        {
            var form = new ObserverFormModel { Name = "Test", Query = "" };

            form.GetValidationError().Should().Contain("query");
        }

        [Fact]
        public void ObserverFormModel_GetValidationError_WhenValid_ShouldReturnNull()
        {
            var form = new ObserverFormModel { Name = "Test", Query = "SELECT * FROM users" };

            form.GetValidationError().Should().BeNull();
        }

        [Fact]
        public void ObserverFormModel_ToObserver_ShouldCreateNewObserver()
        {
            var form = new ObserverFormModel
            {
                Name = "My Observer",
                Query = "SELECT * FROM tasks"
            };

            var observer = form.ToObserver();

            observer.Id.Should().NotBeNullOrEmpty();
            observer.Name.Should().Be("My Observer");
            observer.Query.Should().Be("SELECT * FROM tasks");
        }

        [Fact]
        public void ObserverFormModel_FromObserver_ShouldPopulateFields()
        {
            var existing = new DittoDatabaseObserver("existing-id", "Existing Observer", "SELECT * FROM items");
            var form = new ObserverFormModel();

            form.FromObserver(existing);

            form.Name.Should().Be("Existing Observer");
            form.Query.Should().Be("SELECT * FROM items");
        }

        [Fact]
        public void ObserverFormModel_ToObserver_AfterFromObserver_ShouldPreserveId()
        {
            var existing = new DittoDatabaseObserver("existing-id", "Original", "SELECT * FROM items");
            var form = new ObserverFormModel();
            form.FromObserver(existing);
            form.Name = "Updated Name";

            var result = form.ToObserver();

            result.Id.Should().Be("existing-id");
            result.Name.Should().Be("Updated Name");
        }

        #endregion
    }
}
