using System.Globalization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media;
using SkiaSharp;

namespace Cartrest.Windows;

internal static class Ui
{
    internal static readonly Brush Window = Brush("#111916");
    internal static readonly Brush Panel = Brush("#17211D");
    internal static readonly Brush Input = Brush("#202D27");
    internal static readonly Brush Edge = Brush("#35473D");
    internal static readonly Brush Text = Brush("#EDF5EE");
    internal static readonly Brush Secondary = Brush("#B8CEC0");
    internal static readonly Brush Accent = Brush("#B4E3BA");
    internal static readonly Brush AccentText = Brush("#183025");

    internal static SolidColorBrush Brush(string hex)
    {
        var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
        brush.Freeze();
        return brush;
    }

    internal static Color ColorFrom(SKColor color) => Color.FromArgb(color.Alpha, color.Red, color.Green, color.Blue);

    internal static TextBlock Label(string text, double size = 13, Brush? foreground = null, bool strong = false) => new()
    {
        Text = text,
        FontSize = size,
        Foreground = foreground ?? Text,
        FontWeight = strong ? FontWeights.SemiBold : FontWeights.Normal,
        TextWrapping = TextWrapping.Wrap
    };

    internal static Button Button(string caption, Action action, bool prominent = false, bool active = false)
    {
        var button = new Button
        {
            Content = caption,
            Padding = new Thickness(13, 7, 13, 7),
            MinHeight = 32,
            Margin = new Thickness(0, 0, 6, 0),
            Cursor = Cursors.Hand,
            FontSize = 13,
            FontWeight = prominent || active ? FontWeights.SemiBold : FontWeights.Normal,
            Foreground = prominent || active ? AccentText : Text,
            Background = prominent || active ? Accent : Input,
            BorderBrush = prominent || active ? Accent : Edge,
            BorderThickness = new Thickness(1),
            Template = ButtonTemplate()
        };
        button.Click += (_, _) => action();
        return button;
    }

    private static ControlTemplate? buttonTemplate;
    private static ControlTemplate ButtonTemplate()
    {
        if (buttonTemplate is not null)
            return buttonTemplate;
        var outline = new FrameworkElementFactory(typeof(Border)) { Name = "Outline" };
        outline.SetValue(Border.CornerRadiusProperty, new CornerRadius(7));
        outline.SetBinding(Border.BackgroundProperty, new System.Windows.Data.Binding(nameof(Control.Background)) { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        outline.SetBinding(Border.BorderBrushProperty, new System.Windows.Data.Binding(nameof(Control.BorderBrush)) { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        outline.SetBinding(Border.BorderThicknessProperty, new System.Windows.Data.Binding(nameof(Control.BorderThickness)) { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        outline.SetBinding(Border.PaddingProperty, new System.Windows.Data.Binding(nameof(Control.Padding)) { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        var content = new FrameworkElementFactory(typeof(ContentPresenter));
        content.SetValue(FrameworkElement.HorizontalAlignmentProperty, HorizontalAlignment.Center);
        content.SetValue(FrameworkElement.VerticalAlignmentProperty, VerticalAlignment.Center);
        outline.AppendChild(content);
        var template = new ControlTemplate(typeof(Button)) { VisualTree = outline };
        var focus = new Trigger { Property = UIElement.IsKeyboardFocusedProperty, Value = true };
        focus.Setters.Add(new Setter(Border.BorderBrushProperty, Brush("#FFFFFF"), "Outline"));
        var hover = new Trigger { Property = UIElement.IsMouseOverProperty, Value = true };
        hover.Setters.Add(new Setter(UIElement.OpacityProperty, 0.87, "Outline"));
        var disabled = new Trigger { Property = UIElement.IsEnabledProperty, Value = false };
        disabled.Setters.Add(new Setter(UIElement.OpacityProperty, 0.46, "Outline"));
        template.Triggers.Add(hover);
        template.Triggers.Add(focus);
        template.Triggers.Add(disabled);
        buttonTemplate = template;
        return template;
    }

    // Define native Track parts in markup so WPF wires drag, paging and keyboard commands.
    private static readonly Lazy<ResourceDictionary> TrackStyles = new(() => (ResourceDictionary)XamlReader.Parse("""
        <ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
          <Style x:Key="TrackButton" TargetType="RepeatButton">
            <Setter Property="Focusable" Value="False" />
            <Setter Property="ClickMode" Value="Press" />
            <Setter Property="Template">
              <Setter.Value>
                <ControlTemplate TargetType="RepeatButton">
                  <Border Background="Transparent" />
                </ControlTemplate>
              </Setter.Value>
            </Setter>
          </Style>
          <ControlTemplate x:Key="SliderTrack" TargetType="Slider">
            <Grid Background="Transparent">
              <Border x:Name="Line" Height="4" VerticalAlignment="Center" Background="#35473D" CornerRadius="2" />
              <Track x:Name="PART_Track">
                <Track.DecreaseRepeatButton>
                  <RepeatButton Style="{StaticResource TrackButton}" Command="{x:Static Slider.DecreaseLarge}" />
                </Track.DecreaseRepeatButton>
                <Track.Thumb>
                  <Thumb Width="13" Height="13" VerticalAlignment="Center">
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <Border Background="#B4E3BA" BorderBrush="#183025" BorderThickness="1" CornerRadius="7" />
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Style="{StaticResource TrackButton}" Command="{x:Static Slider.IncreaseLarge}" />
                </Track.IncreaseRepeatButton>
              </Track>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="Line" Property="Background" Value="#B8CEC0" />
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
          <Style x:Key="VerticalScroller" TargetType="ScrollBar">
            <Setter Property="Width" Value="11" />
            <Setter Property="Template">
              <Setter.Value>
                <ControlTemplate TargetType="ScrollBar">
                  <Border Padding="2,0" Background="#17211D">
                    <Track x:Name="PART_Track" Orientation="Vertical" IsDirectionReversed="True">
                      <Track.DecreaseRepeatButton>
                        <RepeatButton Style="{StaticResource TrackButton}" Command="{x:Static ScrollBar.PageUpCommand}" />
                      </Track.DecreaseRepeatButton>
                      <Track.Thumb>
                        <Thumb>
                          <Thumb.Template>
                            <ControlTemplate TargetType="Thumb">
                              <Border Background="#688277" CornerRadius="4" />
                            </ControlTemplate>
                          </Thumb.Template>
                        </Thumb>
                      </Track.Thumb>
                      <Track.IncreaseRepeatButton>
                        <RepeatButton Style="{StaticResource TrackButton}" Command="{x:Static ScrollBar.PageDownCommand}" />
                      </Track.IncreaseRepeatButton>
                    </Track>
                  </Border>
                </ControlTemplate>
              </Setter.Value>
            </Setter>
          </Style>
        </ResourceDictionary>
        """));

    private static ControlTemplate SliderTemplate() => (ControlTemplate)TrackStyles.Value["SliderTrack"];

    internal static Style ScrollbarStyle() => (Style)TrackStyles.Value["VerticalScroller"];

    internal static StackPanel Row(params UIElement[] children)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var child in children)
            row.Children.Add(child);
        return row;
    }

    internal static StackPanel Section(Panel parent, string caption)
    {
        var content = new StackPanel();
        var header = Label(caption, 13, Accent, true);
        header.Margin = new Thickness(0, 0, 0, 8);
        content.Children.Add(header);
        parent.Children.Add(new Border
        {
            Padding = new Thickness(12, 10, 12, 12),
            Margin = new Thickness(0, 0, 0, 10),
            Child = content,
            CornerRadius = new CornerRadius(9),
            Background = Window,
            BorderBrush = Edge,
            BorderThickness = new Thickness(1)
        });
        return content;
    }

    internal static void Add(Panel container, FrameworkElement control, double spacing = 7)
    {
        control.Margin = new Thickness(control.Margin.Left, control.Margin.Top, control.Margin.Right, spacing);
        container.Children.Add(control);
    }

    internal static TextBox Entry(string name, string value, int maxLength = 128)
    {
        var entry = new TextBox
        {
            Text = value,
            MaxLength = maxLength,
            Padding = new Thickness(7, 4, 7, 4),
            FontSize = 13,
            MinHeight = 29,
            Background = Input,
            Foreground = Text,
            CaretBrush = Text,
            BorderBrush = Edge
        };
        AutomationProperties.SetName(entry, name);
        return entry;
    }

    internal static void TextField(Panel container, string name, string value, Action<string> changed)
    {
        Add(container, Label(name, 12, Secondary), 3);
        var entry = Entry(name, value);
        entry.TextChanged += (_, _) => changed(entry.Text);
        Add(container, entry);
    }

    internal static void Number(Panel container, string name, double value, double min, double max, Action<double> changed,
        bool slider = true, bool whole = false)
    {
        var row = new DockPanel { LastChildFill = true };
        var entry = Entry(name, Format(value), 15);
        entry.Width = 69;
        entry.Margin = new Thickness(8, 0, 0, 0);
        var label = Label(name, 12, Secondary);
        label.VerticalAlignment = VerticalAlignment.Center;
        DockPanel.SetDock(entry, Dock.Right);
        row.Children.Add(entry);
        row.Children.Add(label);

        Slider? track = null;
        bool updating = false;
        if (slider)
        {
            track = new Slider
            {
                Minimum = min, Maximum = max, Value = value,
                SmallChange = whole ? 1 : (max - min) / 100,
                LargeChange = Math.Max(1, (max - min) / 10),
                IsSnapToTickEnabled = whole, TickFrequency = 1,
                Foreground = Accent, Margin = new Thickness(0, 1, 0, 4),
                Height = 19, Template = SliderTemplate()
            };
            AutomationProperties.SetName(track, name);
            track.ValueChanged += (_, _) =>
            {
                if (updating)
                    return;
                value = whole ? Math.Round(track.Value) : Math.Round(track.Value, 3);
                entry.Text = Format(value);
                changed(value);
            };
        }

        void Commit()
        {
            if (TryNumber(entry.Text, out var parsed) && parsed >= min && parsed <= max)
            {
                parsed = whole ? Math.Round(parsed) : parsed;
                if (parsed != value)
                {
                    value = parsed;
                    updating = true;
                    if (track is not null)
                        track.Value = value;
                    updating = false;
                    changed(value);
                }
            }
            entry.Text = Format(value);
        }
        entry.LostKeyboardFocus += (_, _) => Commit();
        entry.KeyDown += (_, args) =>
        {
            if (args.Key != Key.Enter)
                return;
            Commit();
            args.Handled = true;
        };
        entry.TextChanged += (_, _) =>
        {
            bool valid = TryNumber(entry.Text, out var x) && x >= min && x <= max;
            entry.BorderBrush = valid ? Edge : Brush("#F7A28D");
            entry.ToolTip = valid ? null : $"Enter a number from {Format(min)} to {Format(max)}.";
        };
        Add(container, row, track is null ? 6 : 1);
        if (track is not null)
            Add(container, track, 4);
    }

    internal static void ColorField(Panel container, string name, SKColor color, Action<SKColor> changed)
    {
        var row = new DockPanel();
        var entry = Entry(name, $"#{color.Red:X2}{color.Green:X2}{color.Blue:X2}", 7);
        entry.Width = 84;
        var swatch = new Border { Width = 18, Height = 18, CornerRadius = new CornerRadius(4), Margin = new Thickness(5, 0, 8, 0) };
        swatch.Background = new SolidColorBrush(ColorFrom(color));
        DockPanel.SetDock(entry, Dock.Right);
        DockPanel.SetDock(swatch, Dock.Right);
        row.Children.Add(entry);
        row.Children.Add(swatch);
        var label = Label(name, 12, Secondary);
        label.VerticalAlignment = VerticalAlignment.Center;
        row.Children.Add(label);
        entry.TextChanged += (_, _) =>
        {
            if (entry.Text is { Length: 7 } && entry.Text.StartsWith('#') && SKColor.TryParse(entry.Text, out var result))
            {
                swatch.Background = new SolidColorBrush(ColorFrom(result));
                entry.BorderBrush = Edge;
                changed(result);
            }
            else
            {
                entry.BorderBrush = Brush("#F7A28D");
            }
        };
        Add(container, row);
    }

    internal static ComboBox Choice<T>(Panel container, string name, IEnumerable<T> options, T selected, Action<T> changed)
    {
        Add(container, Label(name, 12, Secondary), 3);
        var picker = new ComboBox
        {
            ItemsSource = options,
            SelectedItem = selected,
            Foreground = AccentText,
            Background = Input,
            MinHeight = 29,
            Padding = new Thickness(5, 2, 5, 2)
        };
        AutomationProperties.SetName(picker, name);
        picker.SelectionChanged += (_, _) =>
        {
            if (picker.SelectedItem is T value)
                changed(value);
        };
        Add(container, picker);
        return picker;
    }

    internal static string Format(double value) => value.ToString("0.###", CultureInfo.CurrentCulture);

    private static bool TryNumber(string text, out double value) =>
        double.TryParse(text, NumberStyles.Float, CultureInfo.CurrentCulture, out value) ||
        double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out value);
}
