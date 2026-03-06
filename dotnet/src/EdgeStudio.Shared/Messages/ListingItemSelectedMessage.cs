namespace EdgeStudio.Shared.Messages;

public class ListingItemSelectedMessage(object? selectedItem, string itemType)
{
    public object? SelectedItem { get; } = selectedItem;
    public string ItemType { get; } = itemType;
}
