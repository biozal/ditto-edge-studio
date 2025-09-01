using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Messages;
using EdgeStudio.Models;
using EdgeStudio.Services;

namespace EdgeStudio.ViewModels
{
    public partial class EdgeStudioViewModel : ObservableObject
    {
        private readonly INavigationService _navigationService;
        private readonly Lazy<NavigationViewModel> _navigationViewModelLazy;
        private readonly Lazy<SubscriptionViewModel> _subscriptionViewModelLazy;
        private readonly Lazy<CollectionsViewModel> _collectionsViewModelLazy;
        private readonly Lazy<HistoryViewModel> _historyViewModelLazy;
        private readonly Lazy<FavoritesViewModel> _favoritesViewModelLazy;
        private readonly Lazy<IndexViewModel> _indexViewModelLazy;
        private readonly Lazy<ObserversViewModel> _observersViewModelLazy;
        private readonly Lazy<ToolsViewModel> _toolsViewModelLazy;
        private readonly Lazy<QueryViewModel> _queryViewModelLazy;
        
        private DittoDatabaseConfig? _selectedDatabase;
        private RelayCommand? _closeDatabaseCommand;
        private object? _currentListingViewModel;
        private object? _currentDetailViewModel;

        public event EventHandler? CloseDatabaseRequested;

        public EdgeStudioViewModel(
            INavigationService navigationService,
            Lazy<NavigationViewModel> navigationViewModelLazy,
            Lazy<SubscriptionViewModel> subscriptionViewModelLazy,
            Lazy<CollectionsViewModel> collectionsViewModelLazy,
            Lazy<HistoryViewModel> historyViewModelLazy,
            Lazy<FavoritesViewModel> favoritesViewModelLazy,
            Lazy<IndexViewModel> indexViewModelLazy,
            Lazy<ObserversViewModel> observersViewModelLazy,
            Lazy<ToolsViewModel> toolsViewModelLazy,
            Lazy<QueryViewModel> queryViewModelLazy)
        {
            _navigationService = navigationService;
            
            // Store lazy ViewModels - they will only be instantiated when .Value is accessed
            _navigationViewModelLazy = navigationViewModelLazy;
            _subscriptionViewModelLazy = subscriptionViewModelLazy;
            _collectionsViewModelLazy = collectionsViewModelLazy;
            _historyViewModelLazy = historyViewModelLazy;
            _favoritesViewModelLazy = favoritesViewModelLazy;
            _indexViewModelLazy = indexViewModelLazy;
            _observersViewModelLazy = observersViewModelLazy;
            _toolsViewModelLazy = toolsViewModelLazy;
            _queryViewModelLazy = queryViewModelLazy;
            
            // Register for navigation changes
            WeakReferenceMessenger.Default.Register<NavigationChangedMessage>(this, OnNavigationChanged);
            WeakReferenceMessenger.Default.Register<ListingItemSelectedMessage>(this, OnListingItemSelected);
            
            // Don't call UpdateCurrentViews in constructor - this would instantiate ViewModels prematurely
            // Views will be set when a database is actually selected
        }

        public NavigationViewModel NavigationViewModel => _navigationViewModelLazy.Value;
        public SubscriptionViewModel SubscriptionViewModel => _subscriptionViewModelLazy.Value;
        public CollectionsViewModel CollectionsViewModel => _collectionsViewModelLazy.Value;
        public HistoryViewModel HistoryViewModel => _historyViewModelLazy.Value;
        public FavoritesViewModel FavoritesViewModel => _favoritesViewModelLazy.Value;
        public IndexViewModel IndexViewModel => _indexViewModelLazy.Value;
        public ObserversViewModel ObserversViewModel => _observersViewModelLazy.Value;
        public ToolsViewModel ToolsViewModel => _toolsViewModelLazy.Value;
        public QueryViewModel QueryViewModel => _queryViewModelLazy.Value;

        public DittoDatabaseConfig? SelectedDatabase
        {
            get => _selectedDatabase;
            set
            {
                if (_selectedDatabase != value)
                {
                    _selectedDatabase = value;
                    OnPropertyChanged();
                    
                    // When database is selected, refresh the current views to instantiate ViewModels
                    if (_selectedDatabase != null)
                    {
                        // Default to Subscriptions view when database is first selected
                        UpdateCurrentViews(NavigationItemType.Subscriptions);
                    }
                    else
                    {
                        // Clear views when no database selected
                        CurrentListingViewModel = null;
                        CurrentDetailViewModel = null;
                    }
                }
            }
        }
        
        public object? CurrentListingViewModel
        {
            get => _currentListingViewModel;
            set
            {
                if (_currentListingViewModel != value)
                {
                    _currentListingViewModel = value;
                    OnPropertyChanged();
                }
            }
        }
        
        public object? CurrentDetailViewModel
        {
            get => _currentDetailViewModel;
            set
            {
                if (_currentDetailViewModel != value)
                {
                    _currentDetailViewModel = value;
                    OnPropertyChanged();
                }
            }
        }

        public ICommand CloseDatabaseCommand => _closeDatabaseCommand ??= new RelayCommand(() => ExecuteCloseDatabase(null));

        private void ExecuteCloseDatabase(object? parameter)
        {
            CloseDatabaseRequested?.Invoke(this, EventArgs.Empty);
        }
        
        private void OnNavigationChanged(object recipient, NavigationChangedMessage message)
        {
            UpdateCurrentViews(message.NavigationType);
        }
        
        private void OnListingItemSelected(object recipient, ListingItemSelectedMessage message)
        {
            // Update detail view based on selected item
            switch (_navigationService.CurrentNavigationType)
            {
                case NavigationItemType.Subscriptions:
                    CurrentDetailViewModel = message.SelectedItem != null ? SubscriptionViewModel : null;
                    break;
                case NavigationItemType.Collections:
                case NavigationItemType.History:
                case NavigationItemType.Favorites:
                case NavigationItemType.Indexes:
                    CurrentDetailViewModel = message.SelectedItem != null ? QueryViewModel : null;
                    break;
                case NavigationItemType.Observers:
                    CurrentDetailViewModel = message.SelectedItem != null ? ObserversViewModel : null;
                    break;
                case NavigationItemType.Tools:
                    CurrentDetailViewModel = message.SelectedItem != null ? ToolsViewModel : null;
                    break;
            }
        }
        
        private void UpdateCurrentViews(NavigationItemType navigationType)
        {
            // Only instantiate ViewModels when a database is actually selected
            if (_selectedDatabase == null)
            {
                CurrentListingViewModel = null;
                CurrentDetailViewModel = null;
                return;
            }
            
            switch (navigationType)
            {
                case NavigationItemType.Subscriptions:
                    CurrentListingViewModel = SubscriptionViewModel;
                    CurrentDetailViewModel = null;
                    break;
                case NavigationItemType.Collections:
                    CurrentListingViewModel = CollectionsViewModel;
                    CurrentDetailViewModel = null;
                    break;
                case NavigationItemType.History:
                    CurrentListingViewModel = HistoryViewModel;
                    CurrentDetailViewModel = null;
                    break;
                case NavigationItemType.Favorites:
                    CurrentListingViewModel = FavoritesViewModel;
                    CurrentDetailViewModel = null;
                    break;
                case NavigationItemType.Indexes:
                    CurrentListingViewModel = IndexViewModel;
                    CurrentDetailViewModel = null;
                    break;
                case NavigationItemType.Observers:
                    CurrentListingViewModel = ObserversViewModel;
                    CurrentDetailViewModel = null;
                    break;
                case NavigationItemType.Tools:
                    CurrentListingViewModel = ToolsViewModel;
                    CurrentDetailViewModel = null;
                    break;
            }
        }
    }
}