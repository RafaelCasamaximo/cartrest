using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using Microsoft.Win32;

namespace Cartrest.Windows;

internal static class Appearance
{
    // The first nine roles mirror the tokens in DESIGN.md and CartrestTheme.swift.
    private static readonly (string Role, uint Dark, uint Light)[] Colors =
    [
        ("Window", 0x18211F, 0xF4F5F0),
        ("Inspector", 0x202B27, 0xEAF0E9),
        ("Footer", 0x26332E, 0xE3EBE3),
        ("Selection", 0x31493E, 0xD4E8D9),
        ("SelectionEdge", 0x81AD94, 0x547662),
        ("Divider", 0x3B4D45, 0xC4D3C9),
        ("Accent", 0x29734F, 0x24664B),
        ("AccentText", 0xBBDBBF, 0x2A593F),
        ("AccentInk", 0xFFFFFF, 0xFFFFFF),
        ("Toolbar", 0x252927, 0xECEFEA),
        ("Control", 0x303B36, 0xDDE6DD),
        ("Active", 0x485650, 0xC8D8CD),
        ("Hovered", 0x3B4942, 0xD3DFD5),
        ("Field", 0x171E1B, 0xF8FAF6),
        ("FieldEdge", 0x4C6056, 0x819587),
        ("Text", 0xECF1ED, 0x242E28),
        ("Secondary", 0xABB9B0, 0x4D6155),
        ("Focus", 0xA7DAB7, 0x276044),
        ("Track", 0x42534A, 0x849889),
        ("Thumb", 0xEFF3EF, 0x354E40),
        ("Scroller", 0x6D8075, 0x697F73),
        ("Error", 0xFFC0AF, 0x8B3024)
    ];

    private static ResourceDictionary? fluent;

    internal static void Apply(Application app, bool? dark = null)
    {
        bool useDark = dark ?? ReadSystemAppearance();
        bool highContrast = SystemParameters.HighContrast && dark is null;
        string variant = highContrast ? "HC" : useDark ? "Dark" : "Light";
        var source = new Uri($"pack://application:,,,/PresentationFramework.Fluent;component/Themes/Fluent.{variant}.xaml");
        if (fluent?.Source != source)
        {
            if (fluent is not null)
                app.Resources.MergedDictionaries.Remove(fluent);
            fluent = new ResourceDictionary { Source = source };
            app.Resources.MergedDictionaries.Add(fluent);
        }
        foreach (var (role, darkValue, lightValue) in Colors)
        {
            var color = highContrast ? HighContrastColor(role) : Rgb(useDark ? darkValue : lightValue);
            var key = "Cartrest." + role;
            if (app.Resources[key] is SolidColorBrush existing && existing.Color == color)
                continue;
            var brush = new SolidColorBrush(color);
            brush.Freeze();
            app.Resources[key] = brush;
        }
        if (app.MainWindow is { } window)
            UpdateCaption(window, useDark && !highContrast);
    }

    internal static void UpdateCaption(Window window, bool dark)
    {
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == IntPtr.Zero)
            return;
        const int immersiveDarkMode = 20;
        int enabled = dark ? 1 : 0;
        _ = DwmSetWindowAttribute(handle, immersiveDarkMode, ref enabled, sizeof(int));
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr handle, int attribute, ref int value, int size);

    internal static bool ReadSystemAppearance() =>
        Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
            "AppsUseLightTheme", 1) is 0;

    // Dynamic resources retheme controls even when WPF has frozen their composed brushes.
    internal static T Use<T>(T element, DependencyProperty property, string role) where T : FrameworkElement
    {
        element.SetResourceReference(property, "Cartrest." + role);
        return element;
    }

    internal static Color Rgb(uint value) => Color.FromRgb((byte)(value >> 16), (byte)(value >> 8), (byte)value);

    private static Color HighContrastColor(string role) => role switch
    {
        "Accent" => SystemColors.HighlightColor,
        "Selection" or "Active" or "Hovered" => SystemColors.WindowColor,
        "AccentInk" => SystemColors.HighlightTextColor,
        "Text" or "Secondary" or "AccentText" or "Error" => SystemColors.WindowTextColor,
        "Divider" or "SelectionEdge" or "FieldEdge" or "Focus" or "Track" or "Thumb" or "Scroller" => SystemColors.WindowTextColor,
        _ => SystemColors.WindowColor
    };
}
