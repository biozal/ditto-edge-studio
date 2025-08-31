namespace EdgeStudio.Messages;

public class ListingItemSelectedMessage
{
    public object? SelectedItem { get; }
    public string ItemType { get; }
    
    public ListingItemSelectedMessage(object? selectedItem, string itemType)
    {
        SelectedItem = selectedItem;
        ItemType = itemType;
    }
}