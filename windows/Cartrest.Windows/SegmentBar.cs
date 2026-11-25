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
    private readonly List<(T Value, RadioButton Button)> choices = [];
    private readonly string radioGroup = Guid.NewGuid().ToString("N");
    private readonly bool console;
    private bool updating;

    internal SegmentBar(string name, Func<T, string> caption, Action<T> changed, bool expanded = false, bool console = false)
    {
        this.caption = caption;
        this.changed = changed;
        this.console = console;
        strip = expanded ? new UniformGrid { Rows = 1 } : new StackPanel { Orientation = Orientation.Horizontal };
        Background = Ui.Input;
        CornerRadius = new CornerRadius(console ? 15 : 8);
        Padding = new Thickness(3);
        Child = strip;
        AutomationProperties.SetName(this, name);
        KeyboardNavigation.SetTabNavigation(strip, KeyboardNavigationMode.Once);
    }

    internal int Count => choices.Count;

    internal void Load(IEnumerable<T> items, T selected)
    {
        choices.Clear();
        strip.Children.Clear();
        foreach (var value in items)
        {
            string title = caption(value);
            var text = Ui.Label(title, 13, Ui.Text, true);
            text.TextWrapping = TextWrapping.NoWrap;
            text.TextTrimming = TextTrimming.CharacterEllipsis;
            var item = new RadioButton
            {
                Content = text,
                GroupName = radioGroup,
                Padding = console ? new Thickness(14, 4, 14, 4) : new Thickness(6, 4, 6, 4),
                MaxWidth = console ? 209 : double.PositiveInfinity,
                MinHeight = 26,
                Background = Appearance.Brush(console ? "Selection" : "Active"),
                FontSize = 13,
                Cursor = Cursors.Hand,
                Template = Ui.SegmentTemplate(),
                ToolTip = title
            };
            AutomationProperties.SetName(item, title);
            item.Checked += (_, _) =>
            {
                if (!updating)
                    changed(value);
            };
            item.PreviewKeyDown += Move;
            choices.Add((value, item));
            strip.Children.Add(item);
        }
        Select(selected);
    }

    internal void Select(T value)
    {
        updating = true;
        foreach (var (candidate, button) in choices)
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
