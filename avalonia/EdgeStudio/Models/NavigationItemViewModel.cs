using System;
using CommunityToolkit.Mvvm.ComponentModel;

namespace EdgeStudio.Models;

/// <summary>
/// ViewModel wrapper for NavigationItem that includes selection state for efficient binding
/// </summary>
public partial class NavigationItemViewModel : ObservableObject
{
    private readonly NavigationItem _navigationItem;
    
    [ObservableProperty]
    private bool _isSelected;
    
    public NavigationItemViewModel(NavigationItem navigationItem)
    {
        _navigationItem = navigationItem ?? throw new ArgumentNullException(nameof(navigationItem));
    }
    
    public NavigationItemType Type => _navigationItem.Type;
    public string Label => _navigationItem.Label;
    public string Icon => _navigationItem.Icon;
    public string Tooltip => _navigationItem.Tooltip;
    
    /// <summary>
    /// Gets the underlying NavigationItem
    /// </summary>
    public NavigationItem NavigationItem => _navigationItem;
    
    public override bool Equals(object? obj)
    {
        if (obj is NavigationItemViewModel other)
            return Type == other.Type;
        if (obj is NavigationItem item)
            return Type == item.Type;
        return false;
    }
    
    public override int GetHashCode() => Type.GetHashCode();
}