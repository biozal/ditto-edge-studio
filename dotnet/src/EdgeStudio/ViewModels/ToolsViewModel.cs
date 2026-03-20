using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Shared.Messages;
using EdgeStudio.Shared.Services;

namespace EdgeStudio.ViewModels;

public partial class ToolsViewModel : ViewModelBase
{
    [ObservableProperty]
    private string _listingTitle = "Tools Listing";

    [ObservableProperty]
    private string _detailsTitle = "Tool Details";

    [ObservableProperty]
    private object? _selectedItem;

    public ObservableCollection<string> Items { get; }

    public ToolsViewModel(IToastService? toastService = null) : base(toastService)
    {
        Items = new ObservableCollection<string>();
        // Placeholder items for now
        Items.Add("Presence Viewer");
        Items.Add("Disk Usage");
        Items.Add("Permissions Health");
    }

    [RelayCommand]
    private void SelectItem(object? item)
    {
        SelectedItem = item;
        if (item != null)
        {
            WeakReferenceMessenger.Default.Send(new ListingItemSelectedMessage(item, "Tool"));
        }
    }
}