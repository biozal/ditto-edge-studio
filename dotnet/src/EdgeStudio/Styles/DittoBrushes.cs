using Avalonia.Media;

namespace EdgeStudio;

/// <summary>
/// Strongly-typed static brushes for Ditto brand colors.
/// Use these in C# code-behind when you need a brush directly.
///
/// For theme-aware colors (AppBackground, CardSurface), use {DynamicResource} in XAML instead,
/// since their value is only resolved at render time based on the active system theme.
/// </summary>
public static class DittoBrushes
{
    /// <summary>RAL 1016 Sulfur Yellow — primary accent color.</summary>
    public static readonly SolidColorBrush Accent = new(Color.Parse("#F0D830"));

    /// <summary>RAL 9022 Pearl Light Grey — secondary color.</summary>
    public static readonly SolidColorBrush Secondary = new(Color.Parse("#9D9D9F"));

    /// <summary>Raw RAL color values — mirrors Color.Ditto.* from the SwiftUI version.</summary>
    public static class Ditto
    {
        /// <summary>RAL 9005 Jet Black — #0A0A0A</summary>
        public static readonly SolidColorBrush JetBlack = new(Color.Parse("#0A0A0A"));

        /// <summary>RAL 9017 Traffic Black — #2A292A</summary>
        public static readonly SolidColorBrush TrafficBlack = new(Color.Parse("#2A292A"));

        /// <summary>RAL 9022 Pearl Light Grey — #9D9D9F</summary>
        public static readonly SolidColorBrush PearlLightGrey = new(Color.Parse("#9D9D9F"));

        /// <summary>RAL 9018 Papyrus White — #D0CFC8</summary>
        public static readonly SolidColorBrush PapyrusWhite = new(Color.Parse("#D0CFC8"));

        /// <summary>RAL 9016 Traffic White — #F1F0EA</summary>
        public static readonly SolidColorBrush TrafficWhite = new(Color.Parse("#F1F0EA"));

        /// <summary>RAL 1016 Sulfur Yellow — #F0D830</summary>
        public static readonly SolidColorBrush SulfurYellow = new(Color.Parse("#F0D830"));
    }
}
