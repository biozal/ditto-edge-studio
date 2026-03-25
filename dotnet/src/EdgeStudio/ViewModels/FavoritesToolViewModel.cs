using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Shared.Data.Repositories;
using EdgeStudio.Shared.Messages;
using EdgeStudio.Shared.Models;
using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;

namespace EdgeStudio.ViewModels
{
    /// <summary>
    /// ViewModel for the Favorites tool panel.
    /// </summary>
    public partial class FavoritesToolViewModel : ObservableObject
    {
        private readonly IFavoritesRepository _repo;

        public ObservableCollection<QueryHistory> Items { get; } = new();

        public FavoritesToolViewModel(IFavoritesRepository repo)
        {
            _repo = repo;
            _repo.RegisterObserver(Items, err => { /* silently ignore */ });
            WeakReferenceMessenger.Default.Register<AddToFavoritesMessage>(this, OnAddToFavorites);
        }

        private async void OnAddToFavorites(object recipient, AddToFavoritesMessage message)
        {
            var entry = new QueryHistory(
                Guid.NewGuid().ToString(),
                message.Item.Query,
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
        private async Task RemoveFromFavorites(QueryHistory item)
        {
            await _repo.DeleteQueryHistory(item);
        }
    }
}
