using Avalonia.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Shared.Data.Repositories;
using EdgeStudio.Shared.Messages;
using EdgeStudio.Shared.Models;
using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;

namespace EdgeStudio.ViewModels
{
    /// <summary>
    /// ViewModel for the Query History tool panel.
    /// </summary>
    public partial class HistoryToolViewModel : ObservableObject
    {
        private readonly IHistoryRepository _repo;

        public ObservableCollection<QueryHistory> Items { get; } = new();

        public HistoryToolViewModel(IHistoryRepository repo)
        {
            _repo = repo;
            _repo.RegisterObserver(Items, err => { /* silently ignore */ });
            WeakReferenceMessenger.Default.Register<QueryExecutedMessage>(this, OnQueryExecuted);
        }

        private async void OnQueryExecuted(object recipient, QueryExecutedMessage message)
        {
            var query = message.QueryText?.Trim();
            if (string.IsNullOrWhiteSpace(query)) return;

            // Remove any existing entry for the same query (dedup — re-running moves to top)
            var existing = Items.FirstOrDefault(h =>
                string.Equals(h.Query?.Trim(), query, StringComparison.Ordinal));
            if (existing != null)
                await _repo.DeleteQueryHistory(existing);

            var entry = new QueryHistory(
                Guid.NewGuid().ToString(),
                query,
                DateTime.UtcNow.ToString("O"));
            await _repo.AddQueryHistory(entry);
        }

        [RelayCommand]
        private void LoadQuery(QueryHistory item)
        {
            WeakReferenceMessenger.Default.Send(new LoadQueryRequestedMessage(item.Query));
        }

        [RelayCommand]
        private void LoadAndExecuteQuery(QueryHistory item)
        {
            WeakReferenceMessenger.Default.Send(new LoadAndExecuteQueryRequestedMessage(item.Query));
        }

        [RelayCommand]
        private async Task DeleteHistory(QueryHistory item)
        {
            await _repo.DeleteQueryHistory(item);
        }

        [RelayCommand]
        private void AddToFavorites(QueryHistory item)
        {
            WeakReferenceMessenger.Default.Send(new AddToFavoritesMessage(item));
        }
    }
}
