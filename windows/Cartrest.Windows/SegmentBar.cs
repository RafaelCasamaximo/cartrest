using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;

namespace Cartrest.Windows;

/// <summary>A native radio group that keeps the selected workspace in the keyboard focus order.</summary>
internal sealed class SegmentBar<T> : Border where T : notnull
{
    private readonly Panel strip;
    private readonly Func<T, string> caption;
    private readonly Action<T> changed;
    private readonly List<(T Value, RadioButton Button, double CaptionWidth)> choices = [];
    private readonly string radioGroup = Guid.NewGuid().ToString("N");
    private readonly bool console;
    private bool updating;

    internal SegmentBar(string name, Func<T, string> caption, Action<T> changed, bool expanded = false, bool console = false)
    {
        this.caption = caption;
        this.changed = changed;
        this.console = console;
        strip = expanded ? new Grid() : new StackPanel { Orientation = Orientation.Horizontal };
        Appearance.Use(this, BackgroundProperty, "Control");
        CornerRadius = new CornerRadius(console ? 15 : 8);
        Padding = new Thickness(3);
        Child = strip;
        AutomationProperties.SetName(this, name);
        KeyboardNavigation.SetTabNavigation(strip, KeyboardNavigationMode.Once);
    }

    internal int Count => choices.Count;

    internal bool CaptionsFit => choices.All(choice =>
        choice.Button.ActualWidth >= choice.CaptionWidth + choice.Button.Padding.Left + choice.Button.Padding.Right);

    internal void Load(IEnumerable<T> items, T selected)
    {
        choices.Clear();
        strip.Children.Clear();
        var layout = strip as Grid;
        layout?.ColumnDefinitions.Clear();
        foreach (var value in items)
        {
            string title = caption(value);
            var text = Ui.Label(title, 13, strong: true);
            text.FontFamily = new System.Windows.Media.FontFamily("Segoe UI");
            text.TextWrapping = TextWrapping.NoWrap;
            text.TextTrimming = TextTrimming.CharacterEllipsis;
            text.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            var item = new RadioButton
            {
                Content = text,
                GroupName = radioGroup,
                Padding = console ? new Thickness(14, 4, 14, 4) : new Thickness(6, 4, 6, 4),
                MaxWidth = console ? 209 : double.PositiveInfinity,
                // Fluent's standard radio buttons reserve 120 DIPs for their indicator and label.
                MinWidth = 0,
                MinHeight = 26,
                FontSize = 13,
                Cursor = Cursors.Hand,
                Template = Ui.SegmentTemplate(),
                ToolTip = title
            };
            Appearance.Use(item, Control.BackgroundProperty, console ? "Selection" : "Active");
            AutomationProperties.SetName(item, title);
            if (layout is not null)
            {
                // Give longer labels more room while letting the whole selector track the inspector width.
                layout.ColumnDefinitions.Add(new()
                {
                    Width = new GridLength(Math.Max(53, text.DesiredSize.Width + 25), GridUnitType.Star)
                });
                Grid.SetColumn(item, layout.ColumnDefinitions.Count - 1);
            }
            item.Checked += (_, _) =>
            {
                if (!updating)
                    changed(value);
            };
            item.PreviewKeyDown += Move;
            choices.Add((value, item, text.DesiredSize.Width));
            strip.Children.Add(item);
        }
        Select(selected);
    }

    internal void Select(T value)
    {
        updating = true;
        foreach (var (candidate, button, _) in choices)
        {
            bool selected = EqualityComparer<T>.Default.Equals(candidate, value);
            button.IsChecked = selected;
            button.IsTabStop = selected;
        }
        updating = false;
    }

    private void Move(object sender, KeyEventArgs args)
    {
        int current = choices.FindIndex(choice => ReferenceEquals(choice.Button, sender));
        int next = args.Key switch
        {
            Key.Left => (current + choices.Count - 1) % choices.Count,
            Key.Right => (current + 1) % choices.Count,
            Key.Home => 0,
            Key.End => choices.Count - 1,
            _ => -1
        };
        if (next < 0)
            return;
        var button = choices[next].Button;
        button.Focus();
        button.IsChecked = true;
        args.Handled = true;
    }
}
