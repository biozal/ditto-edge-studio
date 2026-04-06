using System;
using System.Collections.Generic;
using System.Linq;

namespace EdgeStudio.Shared.Models
{
    /// <summary>
    /// Represents a single observer event containing diff data from a Ditto store observer callback.
    /// Events are session-only (not persisted to SQLite) and accumulate in memory.
    /// </summary>
    public class ObserverEvent
    {
        /// <summary>
        /// Unique identifier for this event.
        /// </summary>
        public string Id { get; init; } = Guid.NewGuid().ToString();

        /// <summary>
        /// Links to the parent observer that generated this event.
        /// </summary>
        public string ObserverId { get; init; } = string.Empty;

        /// <summary>
        /// JSON strings of all result items from the observer callback.
        /// </summary>
        public List<string> Data { get; init; } = new();

        /// <summary>
        /// Indexes of newly inserted items in the data list.
        /// </summary>
        public List<int> InsertIndexes { get; init; } = new();

        /// <summary>
        /// Indexes of updated items in the data list.
        /// </summary>
        public List<int> UpdatedIndexes { get; init; } = new();

        /// <summary>
        /// Indexes of deleted items (relative to the previous result set).
        /// </summary>
        public List<int> DeletedIndexes { get; init; } = new();

        /// <summary>
        /// Moved items as (From, To) index pairs.
        /// </summary>
        public List<(int From, int To)> MovedIndexes { get; init; } = new();

        /// <summary>
        /// When the event was received.
        /// </summary>
        public DateTime EventTime { get; init; } = DateTime.Now;

        /// <summary>
        /// Formatted event time string for display.
        /// </summary>
        public string FormattedEventTime => EventTime.ToString("HH:mm:ss.fff");

        /// <summary>
        /// Returns only the data items at the inserted indexes.
        /// </summary>
        public List<string> GetInsertedData() => GetDataAtIndexes(InsertIndexes);

        /// <summary>
        /// Returns only the data items at the updated indexes.
        /// </summary>
        public List<string> GetUpdatedData() => GetDataAtIndexes(UpdatedIndexes);

        private List<string> GetDataAtIndexes(List<int> indexes)
        {
            if (Data.Count == 0 || indexes.Count == 0)
                return new List<string>();

            return indexes
                .Where(i => i >= 0 && i < Data.Count)
                .Select(i => Data[i])
                .ToList();
        }
    }
}
