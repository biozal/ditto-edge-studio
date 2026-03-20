using System;
using System.Globalization;
using Avalonia.Data.Converters;
using Avalonia.Media;

namespace EdgeStudio.Converters
{
    /// <summary>Converts a bool (UsedIndex) to a green/orange brush for the badge background.</summary>
    public class BoolToIndexColorConverter : IValueConverter
    {
        public static readonly BoolToIndexColorConverter Instance = new();

        public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        {
            if (value is bool b)
                return b
                    ? new SolidColorBrush(Color.Parse("#4CAF50"))
                    : new SolidColorBrush(Color.Parse("#FF9800"));
            return null;
        }

        public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
            throw new NotImplementedException();
    }

    /// <summary>Converts a bool (UsedIndex) to a "✓ Indexed" / "✗ Not Indexed" label.</summary>
    public class BoolToIndexLabelConverter : IValueConverter
    {
        public static readonly BoolToIndexLabelConverter Instance = new();

        public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        {
            if (value is bool b)
                return b ? "✓ Indexed" : "✗ Not Indexed";
            return string.Empty;
        }

        public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
            throw new NotImplementedException();
    }
}
