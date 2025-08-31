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
        private DittoDatabaseConfig? _selectedDatabase;
        private RelayCommand? _closeDatabaseCommand;
        private object? _currentListingViewModel;
        private object? _currentDetailViewModel;

        public event EventHandler? CloseDatabaseRequested;

        public EdgeStudioViewModel(INavigationService navigationService)
        {
            _navigationService = navigationService;
            
            // Initialize ViewModels
            NavigationViewModel = new NavigationViewModel(_navigationService);
            SubscriptionViewModel = new SubscriptionViewModel();
            CollectionsViewModel = new CollectionsViewModel();
            HistoryViewModel = new HistoryViewModel();
            FavoritesViewModel = new FavoritesViewModel();
            IndexViewModel = new IndexViewModel();
            ObserversViewModel = new ObserversViewModel();
            ToolsViewModel = new ToolsViewModel();
            QueryViewModel = new QueryViewModel();
            
            // Register for navigation changes
            WeakReferenceMessenger.Default.Register<NavigationChangedMessage>(this, OnNavigationChanged);
            WeakReferenceMessenger.Default.Register<ListingItemSelectedMessage>(this, OnListingItemSelected);
            
            // Set initial view
            UpdateCurrentViews(NavigationItemType.Collections);
        }

        public NavigationViewModel NavigationViewModel { get; }
        public SubscriptionViewModel SubscriptionViewModel { get; }
        public CollectionsViewModel CollectionsViewModel { get; }
        public HistoryViewModel HistoryViewModel { get; }
        public FavoritesViewModel FavoritesViewModel { get; }
        public IndexViewModel IndexViewModel { get; }
        public ObserversViewModel ObserversViewModel { get; }
        public ToolsViewModel ToolsViewModel { get; }
        public QueryViewModel QueryViewModel { get; }

        public DittoDatabaseConfig? SelectedDatabase
        {
            get => _selectedDatabase;
            set
            {
                if (_selectedDatabase != value)
                {
                    _selectedDatabase = value;
                    OnPropertyChanged();
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