using System;
using CommunityToolkit.Mvvm.ComponentModel;

namespace EdgeStudio.Shared.Models
{
    /// <summary>
    /// Form binding model for the Add/Edit Observer dialog.
    /// </summary>
    public partial class ObserverFormModel : ObservableObject
    {
        [ObservableProperty]
        private string name = string.Empty;

        [ObservableProperty]
        private string query = string.Empty;

        /// <summary>
        /// The ID of the observer being edited, or null for new observers.
        /// </summary>
        private string? _editingId = null;

        /// <summary>
        /// Resets the form to default values.
        /// </summary>
        public void Reset()
        {
            Name = string.Empty;
            Query = string.Empty;
            _editingId = null;
        }

        /// <summary>
        /// Creates a DittoDatabaseObserver from the form data.
        /// </summary>
        public DittoDatabaseObserver ToObserver()
        {
            return new DittoDatabaseObserver(
                Id: _editingId ?? Guid.NewGuid().ToString(),
                Name: Name,
                Query: Query);
        }

        /// <summary>
        /// Populates the form with data from an existing observer (for editing).
        /// </summary>
        public void FromObserver(DittoDatabaseObserver observer)
        {
            Name = observer.Name;
            Query = observer.Query;
            _editingId = observer.Id;
        }

        /// <summary>
        /// Validates the form data.
        /// </summary>
        public bool IsValid()
        {
            return !string.IsNullOrWhiteSpace(Name) && !string.IsNullOrWhiteSpace(Query);
        }

        /// <summary>
        /// Gets validation error message if form is invalid.
        /// </summary>
        public string? GetValidationError()
        {
            if (string.IsNullOrWhiteSpace(Name))
                return "Observer name is required.";

            if (string.IsNullOrWhiteSpace(Query))
                return "DQL query is required.";

            return null;
        }
    }
}
