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
    internal static SolidColorBrush Brush(string hex)
    {
        var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
        brush.Freeze();
        return brush;
    }

    internal static Color ColorFrom(SKColor color) => Color.FromArgb(color.Alpha, color.Red, color.Green, color.Blue);

    internal static TextBlock Label(string text, double size = 13, string role = "Text", bool strong = false) =>
        Appearance.Use(new TextBlock
        {
            Text = text,
            FontSize = size,
            FontWeight = strong ? FontWeights.SemiBold : FontWeights.Normal,
            TextWrapping = TextWrapping.Wrap
        }, TextBlock.ForegroundProperty, role);

    internal static Button Button(string caption, Action action, bool prominent = false)
    {
        var button = new Button
        {
            Content = caption,
            Padding = new Thickness(12, 4, 12, 5),
            MinHeight = 28,
            Margin = new Thickness(0, 0, 7, 0),
            Cursor = Cursors.Hand,
            FontSize = 13,
            FontWeight = FontWeights.Medium,
            Template = (ControlTemplate)ControlStyles.Value["Action"]
        };
        Appearance.Use(button, Control.ForegroundProperty, prominent ? "AccentInk" : "Text");
        Appearance.Use(button, Control.BackgroundProperty, prominent ? "Accent" : "Control");
        button.Click += (_, _) => action();
        return button;
    }

    internal static Button IconButton(string glyph, string name, Action action)
    {
        var button = Button("", action);
        button.Content = new TextBlock
        {
            Text = glyph, FontFamily = new FontFamily("Segoe Fluent Icons"), FontSize = 14
        };
        button.MinWidth = 28;
        button.Padding = new Thickness(6, 4, 6, 4);
        AutomationProperties.SetName(button, name);
        button.ToolTip = name;
        return button;
    }

    // Define native Track parts in markup so WPF wires drag, paging and keyboard commands.
    private static readonly Lazy<ResourceDictionary> ControlStyles = new(() => (ResourceDictionary)XamlReader.Parse("""
        <ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
          <ControlTemplate x:Key="Action" TargetType="Button">
            <Border x:Name="Surface" CornerRadius="7" Background="{TemplateBinding Background}"
                    BorderBrush="Transparent" BorderThickness="1" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" />
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Surface" Property="Opacity" Value=".82" /></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="Surface" Property="Opacity" Value=".68" /></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Surface" Property="BorderBrush" Value="{DynamicResource Cartrest.Focus}" /></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="Surface" Property="Opacity" Value=".5" /></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
          <ControlTemplate x:Key="Segment" TargetType="RadioButton">
            <Grid>
              <Border x:Name="Surface" CornerRadius="6" BorderThickness="1" BorderBrush="Transparent"
                      Background="Transparent" Padding="{TemplateBinding Padding}">
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" />
              </Border>
              <Border x:Name="Active" Height="2" Width="12" VerticalAlignment="Bottom" Margin="0,0,0,1"
                      Background="{DynamicResource Cartrest.Focus}" CornerRadius="1" Visibility="Collapsed" />
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Surface" Property="Background" Value="{DynamicResource Cartrest.Hovered}" /></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Surface" Property="Background" Value="{Binding Background, RelativeSource={RelativeSource TemplatedParent}}" />
                <Setter TargetName="Active" Property="Visibility" Value="Visible" />
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Surface" Property="BorderBrush" Value="{DynamicResource Cartrest.Focus}" /></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
          <Style x:Key="ArtworkItem" TargetType="ListBoxItem">
            <Setter Property="Margin" Value="0,0,0,5" />
            <Setter Property="HorizontalContentAlignment" Value="Stretch" />
            <Setter Property="Template">
              <Setter.Value>
                <ControlTemplate TargetType="ListBoxItem">
                  <Border x:Name="Surface" Background="Transparent" CornerRadius="8" Padding="6"
                          BorderThickness="1" BorderBrush="{DynamicResource Cartrest.Divider}">
                    <ContentPresenter />
                  </Border>
                  <ControlTemplate.Triggers>
                    <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Surface" Property="Background" Value="{DynamicResource Cartrest.Hovered}" /></Trigger>
                    <Trigger Property="IsSelected" Value="True">
                      <Setter TargetName="Surface" Property="Background" Value="{DynamicResource Cartrest.Selection}" />
                      <Setter TargetName="Surface" Property="BorderBrush" Value="{DynamicResource Cartrest.SelectionEdge}" />
                    </Trigger>
                    <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Surface" Property="BorderBrush" Value="{DynamicResource Cartrest.Focus}" /></Trigger>
                  </ControlTemplate.Triggers>
                </ControlTemplate>
              </Setter.Value>
            </Setter>
          </Style>
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
              <Border x:Name="Line" Height="4" VerticalAlignment="Center" Background="{DynamicResource Cartrest.Track}" CornerRadius="2" />
              <Track x:Name="PART_Track">
                <Track.DecreaseRepeatButton>
                  <RepeatButton Style="{StaticResource TrackButton}" Command="{x:Static Slider.DecreaseLarge}" />
                </Track.DecreaseRepeatButton>
                <Track.Thumb>
                  <Thumb Width="13" Height="13" VerticalAlignment="Center">
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <Border Background="{DynamicResource Cartrest.Thumb}" BorderBrush="{DynamicResource Cartrest.FieldEdge}" BorderThickness="1" CornerRadius="7" />
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
                <Setter TargetName="Line" Property="Background" Value="{DynamicResource Cartrest.Focus}" />
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
          <Style x:Key="VerticalScroller" TargetType="ScrollBar">
            <Setter Property="Width" Value="9" />
            <Setter Property="Template">
              <Setter.Value>
                <ControlTemplate TargetType="ScrollBar">
                  <Border Padding="2,0" Background="Transparent">
                    <Track x:Name="PART_Track" Orientation="Vertical" IsDirectionReversed="True">
                      <Track.DecreaseRepeatButton>
                        <RepeatButton Style="{StaticResource TrackButton}" Command="{x:Static ScrollBar.PageUpCommand}" />
                      </Track.DecreaseRepeatButton>
                      <Track.Thumb>
                        <Thumb>
                          <Thumb.Template>
                            <ControlTemplate TargetType="Thumb">
                              <Border Background="{DynamicResource Cartrest.Scroller}" CornerRadius="4" />
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

    private static ControlTemplate SliderTemplate() => (ControlTemplate)ControlStyles.Value["SliderTrack"];

    internal static Style ArtworkItemStyle() => (Style)ControlStyles.Value["ArtworkItem"];

    internal static ControlTemplate SegmentTemplate() => (ControlTemplate)ControlStyles.Value["Segment"];

    internal static Style ScrollbarStyle() => (Style)ControlStyles.Value["VerticalScroller"];

    internal static StackPanel Row(params UIElement[] children)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var child in children)
            row.Children.Add(child);
        return row;
    }

    internal static WrapPanel Actions(params UIElement[] children)
    {
        var row = new WrapPanel();
        foreach (var child in children)
            row.Children.Add(child);
        return row;
    }

    internal static StackPanel Section(Panel parent, string caption, FrameworkElement? accessory = null)
    {
        var content = new StackPanel();
        var heading = new DockPanel { Margin = new Thickness(0, 0, 0, 9) };
        var title = Label(caption, 14, strong: true);
        title.VerticalAlignment = VerticalAlignment.Center;
        AutomationProperties.SetHeadingLevel(title, AutomationHeadingLevel.Level2);
        if (accessory is not null)
        {
            DockPanel.SetDock(accessory, Dock.Right);
            heading.Children.Add(accessory);
        }
        heading.Children.Add(title);
        content.Children.Add(heading);
        var section = new Border
        {
            Padding = new Thickness(0, 13, 0, 13),
            Child = content,
            BorderThickness = new Thickness(0, parent.Children.Count > 0 ? 1 : 0, 0, 0)
        };
        parent.Children.Add(Appearance.Use(section, Border.BorderBrushProperty, "Divider"));
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
            Padding = new Thickness(8, 4, 8, 4),
            FontSize = 13,
            MinHeight = 28
        };
        Appearance.Use(entry, Control.BackgroundProperty, "Field");
        Appearance.Use(entry, Control.ForegroundProperty, "Text");
        Appearance.Use(entry, TextBox.CaretBrushProperty, "Text");
        Appearance.Use(entry, Control.BorderBrushProperty, "FieldEdge");
        AutomationProperties.SetName(entry, name);
        return entry;
    }

    internal static void TextField(Panel container, string name, string value, Action<string> changed)
    {
        Add(container, Label(name, 13), 4);
        var entry = Entry(name, value);
        entry.TextChanged += (_, _) => changed(entry.Text);
        Add(container, entry);
    }

    internal static void Number(Panel container, string name, double value, double min, double max, Action<double> changed,
        bool slider = true, bool whole = false, string? unit = null)
    {
        var row = new DockPanel { LastChildFill = true };
        string accessibleName = unit is null ? name : $"{name} ({unit})";
        var entry = Entry(accessibleName, Format(value), 15);
        entry.Width = slider ? 59 : 79;
        entry.TextAlignment = TextAlignment.Right;
        entry.Margin = new Thickness(8, 0, 0, 0);
        var label = Label(name, 13);
        label.VerticalAlignment = VerticalAlignment.Center;
        if (unit is not null)
        {
            var suffix = Label(unit, 11, "Secondary");
            suffix.MinWidth = 14;
            suffix.Margin = new Thickness(4, 0, 0, 0);
            suffix.VerticalAlignment = VerticalAlignment.Center;
            DockPanel.SetDock(suffix, Dock.Right);
            row.Children.Add(suffix);
        }
        DockPanel.SetDock(entry, Dock.Right);
        row.Children.Add(entry);
        DockPanel.SetDock(label, Dock.Left);
        row.Children.Add(label);

        Slider? track = null;
        bool updating = false;
        if (slider)
        {
            label.Width = 112;
            track = new Slider
            {
                Minimum = min, Maximum = max, Value = value,
                SmallChange = whole ? 1 : (max - min) / 100,
                LargeChange = (max - min) / 10,
                IsSnapToTickEnabled = whole, TickFrequency = 1,
                Template = SliderTemplate(), Height = 24, VerticalAlignment = VerticalAlignment.Center
            };
            AutomationProperties.SetName(track, accessibleName);
            row.Children.Add(track);
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
            Appearance.Use(entry, Control.BorderBrushProperty, valid ? "FieldEdge" : "Error");
            entry.ToolTip = valid ? null : $"Enter a number from {Format(min)} to {Format(max)}.";
        };
        Add(container, row, 5);
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
        var label = Label(name, 12, "Secondary");
        label.VerticalAlignment = VerticalAlignment.Center;
        row.Children.Add(label);
        entry.TextChanged += (_, _) =>
        {
            if (entry.Text is { Length: 7 } && entry.Text.StartsWith('#') && SKColor.TryParse(entry.Text, out var result))
            {
                swatch.Background = new SolidColorBrush(ColorFrom(result));
                Appearance.Use(entry, Control.BorderBrushProperty, "FieldEdge");
                changed(result);
            }
            else
            {
                Appearance.Use(entry, Control.BorderBrushProperty, "Error");
            }
        };
        Add(container, row);
    }

    internal static ComboBox Choice<T>(Panel container, string name, IEnumerable<T> options, T selected, Action<T> changed)
    {
        Add(container, Label(name, 13), 4);
        var picker = new ComboBox
        {
            ItemsSource = options,
            SelectedItem = selected,
            MinHeight = 29,
            Padding = new Thickness(8, 3, 8, 3)
        };
        Appearance.Use(picker, Control.BackgroundProperty, "Control");
        Appearance.Use(picker, Control.ForegroundProperty, "Text");
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
