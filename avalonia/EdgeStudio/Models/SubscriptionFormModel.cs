using System;
using CommunityToolkit.Mvvm.ComponentModel;

namespace EdgeStudio.Models
{
    public partial class SubscriptionFormModel : ObservableObject
    {
        [ObservableProperty]
        private string name = string.Empty;
        
        [ObservableProperty]
        private string query = string.Empty;
        
        /// <summary>
        /// Resets the form to default values
        /// </summary>
        public void Reset()
        {
            Name = string.Empty;
            Query = string.Empty;
        }
        
        /// <summary>
        /// Creates a DittoDatabaseSubscription from the form data
        /// </summary>
        /// <returns>New DittoDatabaseSubscription with generated ID</returns>
        public DittoDatabaseSubscription ToSubscription()
        {
            return new DittoDatabaseSubscription(
                Id: Guid.NewGuid().ToString(),
                Name: Name,
                Query: Query
            );
        }
        
        /// <summary>
        /// Populates the form with data from an existing subscription (for editing)
        /// </summary>
        /// <param name="subscription">The subscription to edit</param>
        public void FromSubscription(DittoDatabaseSubscription subscription)
        {
            Name = subscription.Name;
            Query = subscription.Query;
        }
        
        /// <summary>
        /// Validates the form data
        /// </summary>
        /// <returns>True if valid, false otherwise</returns>
        public bool IsValid()
        {
            return !string.IsNullOrWhiteSpace(Name) && !string.IsNullOrWhiteSpace(Query);
        }
        
        /// <summary>
        /// Gets validation error message if form is invalid
        /// </summary>
        /// <returns>Error message or null if valid</returns>
        public string? GetValidationError()
        {
            if (string.IsNullOrWhiteSpace(Name))
                return "Subscription name is required.";
            
            if (string.IsNullOrWhiteSpace(Query))
                return "DQL query is required.";
                
            return null;
        }
    }
}