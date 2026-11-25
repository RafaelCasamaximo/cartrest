using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;

using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Shapes;

namespace Cartrest.Windows;

internal sealed class MeasurementDisplay : Border
{
    internal const double BottomMargin = 23;
    internal const double PreviewClearance = 103;
    private static readonly Brush Ink = Ui.Brush("#1C3019");
    private readonly UniformGrid columns = new() { Rows = 1 };
    private readonly Border[] readers = new Border[3];
    private readonly TextBlock[] names = new TextBlock[3];
    private readonly TextBlock[] values = new TextBlock[3];

    internal MeasurementDisplay()
    {
        MaxWidth = 490;
        Margin = new Thickness(16, 0, 16, BottomMargin);
        Padding = new Thickness(11, 9, 11, 9);
        HorizontalAlignment = HorizontalAlignment.Center;
        VerticalAlignment = VerticalAlignment.Bottom;
        CornerRadius = new CornerRadius(15);
        Background = new LinearGradientBrush(new GradientStopCollection
        {
            new(Color.FromRgb(73, 82, 77), 0), new(Color.FromRgb(43, 53, 47), .17),
            new(Color.FromRgb(23, 32, 28), .92), new(Color.FromRgb(35, 44, 39), 1)
        }, new Point(.5, 0), new Point(.5, 1));
        BorderBrush = new LinearGradientBrush(Color.FromArgb(111, 223, 236, 224), Color.FromArgb(226, 14, 21, 17), 90);
        BorderThickness = new Thickness(1);
        Effect = new DropShadowEffect { BlurRadius = 20, ShadowDepth = 7, Opacity = .43, Color = Color.FromRgb(2, 12, 8) };

        var screen = new Border
        {
            Background = new LinearGradientBrush(Color.FromRgb(215, 228, 184), Color.FromRgb(163, 187, 128), 50),
            BorderBrush = new LinearGradientBrush(Color.FromRgb(105, 118, 88), Color.FromRgb(229, 239, 202), 90),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(4, 3, 4, 3),
            Child = columns
        };

        for (int i = 0; i < readers.Length; i++)
        {
            names[i] = Ui.Label("", 11.5, strong: true);
            names[i].TextWrapping = TextWrapping.NoWrap;
            values[i] = Ui.Label("", 15, strong: true);
            names[i].Foreground = values[i].Foreground = Ink;
            values[i].FontFamily = new FontFamily("Consolas");
            values[i].TextWrapping = TextWrapping.NoWrap;
            var cell = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            cell.Children.Add(names[i]);
            cell.Children.Add(values[i]);
            readers[i] = new Border
            {
                Padding = new Thickness(9, 3, 9, 3),
                BorderBrush = Ui.Brush("#779064"),
                BorderThickness = i == 0 ? new Thickness() : new Thickness(1, 0, 0, 0),
                Child = new Viewbox
                {
                    Stretch = Stretch.Uniform,
                    StretchDirection = StretchDirection.DownOnly,
                    HorizontalAlignment = HorizontalAlignment.Left,
                    VerticalAlignment = VerticalAlignment.Center,
                    Child = cell
                }
            };
            columns.Children.Add(readers[i]);
        }

        var housing = new Grid();
        housing.ColumnDefinitions.Add(new() { Width = new GridLength(19) });
        housing.ColumnDefinitions.Add(new() { Width = new GridLength(1, GridUnitType.Star), MinWidth = 180 });
        housing.ColumnDefinitions.Add(new() { Width = new GridLength(19) });
        housing.Children.Add(Screw(-28));
        Grid.SetColumn(screen, 1);
        housing.Children.Add(screen);
        var right = Screw(31);
        Grid.SetColumn(right, 2);
        housing.Children.Add(right);
        Child = housing;
    }

    internal void Update(params (string Name, string Value)[] readings)
    {
        columns.Columns = readings.Length;
        for (int i = 0; i < readers.Length; i++)
        {
            readers[i].Visibility = i < readings.Length ? Visibility.Visible : Visibility.Collapsed;
            if (i < readings.Length)
                (names[i].Text, values[i].Text) = readings[i];
        }
    }

    private static Grid Screw(double angle)
    {
        var screw = new Grid
        {
            Width = 9,
            Height = 9,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            RenderTransformOrigin = new Point(.5, .5),
            RenderTransform = new RotateTransform(angle),
            IsHitTestVisible = false
        };
        screw.Children.Add(new Ellipse
        {
            Fill = new LinearGradientBrush(Color.FromRgb(163, 169, 162), Color.FromRgb(66, 72, 67), 90),
            Stroke = Ui.Brush("#252F28"), StrokeThickness = 1
        });
        screw.Children.Add(new Rectangle
        {
            Width = 5, Height = 1, Fill = Ui.Brush("#303631"),
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center
        });
        return screw;
    }
}
