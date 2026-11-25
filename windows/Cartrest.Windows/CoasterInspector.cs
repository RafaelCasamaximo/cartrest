using System.IO;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using Cartrest.Core;
using Microsoft.Win32;

namespace Cartrest.Windows;

internal sealed partial class MainWindow
{
    private ListBox? artworkList;
    private TextBlock? artworkCount;

    private void BuildCoasterInspector()
    {
        artworkCount = Ui.Label("", 12, Ui.AccentText, true);
        artworkCount.VerticalAlignment = VerticalAlignment.Center;
        var artwork = Ui.Section(tools, "Sheet artwork", artworkCount);
        artworkList = null;
        if (current.Artwork.Count > 0)
        {
            var list = new ListBox
            {
                MaxHeight = 175, MinHeight = 46, Padding = new Thickness(0),
                Background = Brushes.Transparent, BorderThickness = new Thickness(0),
                Foreground = Ui.Text, ItemContainerStyle = Ui.ArtworkItemStyle(),
                HorizontalContentAlignment = HorizontalAlignment.Stretch
            };
            artworkList = list;
            ScrollViewer.SetHorizontalScrollBarVisibility(list, ScrollBarVisibility.Disabled);
            list.Resources[typeof(System.Windows.Controls.Primitives.ScrollBar)] = Ui.ScrollbarStyle();
            AutomationProperties.SetName(list, "Sheet artwork");
            foreach (var item in current.Artwork)
            {
                var thumbnail = new Image
                {
                    Source = ProofRenderer.Thumbnail(item), Width = 38, Height = 38, Stretch = Stretch.UniformToFill
                };
                thumbnail.Clip = new RectangleGeometry(new Rect(0, 0, 38, 38), 6, 6);
                var line = Ui.Label(item.Name, 13, Ui.Text, true);
                line.TextTrimming = TextTrimming.CharacterEllipsis;
                line.TextWrapping = TextWrapping.NoWrap;
                var dimensions = Ui.Label($"{item.Bitmap.Width:N0} × {item.Bitmap.Height:N0} px", 11, Ui.Secondary);
                var copy = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
                copy.Children.Add(line);
                copy.Children.Add(dimensions);
                var row = new DockPanel { ToolTip = item.Name };
                AutomationProperties.SetName(row, item.Name);
                thumbnail.Margin = new Thickness(0, 0, 8, 0);
                row.Children.Add(thumbnail);
                row.Children.Add(copy);
                list.Items.Add(new ListBoxItem { Content = row });
            }
            list.SelectedIndex = current.Selected;
            list.SelectionChanged += (_, _) =>
            {
                if (list.SelectedIndex < 0 || list.SelectedIndex == current.Selected)
                    return;
                var keyboard = list.IsKeyboardFocusWithin;
                current.Selected = list.SelectedIndex;
                RebuildInspector();
                if (keyboard)
                    Dispatcher.InvokeAsync(RestoreArtworkFocus, DispatcherPriority.Loaded);
            };
            Ui.Add(artwork, list, 5);
        }
        else
        {
            Ui.Add(artwork, Ui.Label("Add a cartridge label or cover image to start a sheet.", 13, Ui.Secondary), 10);
        }

        Button examples = null!;
        examples = Ui.Button("Examples…", () => ShowSamples(examples));
        examples.IsEnabled = Directory.Exists(SampleDirectory()) || current.Profile.SampleArtwork is not null;
        var add = Ui.Button("Add images…", AddImages);
        var actions = Ui.Actions(add, examples);
        if (current.SelectedArtwork is not null)
            actions.Children.Add(Ui.Button("Remove", RemoveSelected));
        Ui.Add(artwork, actions, 0);

        if (current.SelectedArtwork is { } image)
        {
            var reset = Ui.Button("Reset", () =>
            {
                Frame(a => a with { Zoom = 1, PanX = 0, PanY = 0 });
                RebuildInspector();
            });
            AutomationProperties.SetName(reset, "Reset artwork framing");
            var framing = Ui.Section(tools, "Framing", reset);
            Ui.Number(framing, "Zoom", image.Zoom * 100, 100, 350, v => Frame(a => a with { Zoom = v / 100 }), unit: "%");
            Ui.Number(framing, "Horizontal", image.PanX * 100, -100, 100, v => Frame(a => a with { PanX = v / 100 }), unit: "%");
            Ui.Number(framing, "Vertical", image.PanY * 100, -100, 100, v => Frame(a => a with { PanY = v / 100 }), unit: "%");
            Ui.Number(framing, "Copies of this artwork", image.Copies, 1, MaximumCopies(image), v =>
                Frame(a => a with { Copies = (int)v }), slider: false, whole: true);
        }

        PrintControls(Ui.Section(tools, "Printing"));
        var size = Ui.Section(tools, "Model dimensions");
        var range = current.Profile.WidthRange;
        Ui.Number(size, "Coaster width", current.Width, range.Min, range.Max, x => Changed(() => current.Width = x), unit: "mm");
        var check = new CheckBox { Content = "Custom print trim", Foreground = Ui.Text, IsChecked = current.CustomTrim };
        check.Click += (_, _) =>
        {
            if (!current.CustomTrim)
                current.CustomLabel = current.Profile.LabelAt(current.Width) with { X = 0, Y = 0 };
            current.CustomTrim = check.IsChecked == true;
            RebuildInspector();
        };
        Ui.Add(size, check, 4);
        if (current.CustomTrim)
        {
            Ui.Add(size, Ui.Label("The coaster keeps its scaled recess. These values control the print cut.", 12, Ui.Secondary));
            Ui.Number(size, "Trim width (mm)", current.CustomLabel.Width, 20, 160,
                v => Changed(() => current.CustomLabel = current.CustomLabel with { Width = v }), false);
            Ui.Number(size, "Trim height (mm)", current.CustomLabel.Height, 20, 160,
                v => Changed(() => current.CustomLabel = current.CustomLabel with { Height = v }), false);
            Ui.Number(size, "Corner radius (mm)", current.CustomLabel.Radius, 0, 80,
                v => Changed(() => current.CustomLabel = current.CustomLabel with { Radius = v }), false);
            Ui.Number(size, "Lower-left chamfer (mm)", current.CustomLabel.Chamfer, 0, 160,
                v => Changed(() => current.CustomLabel = current.CustomLabel with { Chamfer = v }), false);
        }
        if (current.Mode == ProofMode.ThreeD)
            Ui.Add(size, Ui.Button("Reset 3D view", orbit.Reset), 0);

        pdfAction = Ui.Button("Save A4 PDF…", SavePdf, prominent: true);
        var png = Ui.Button("Save PNG…", SavePng);
        pngActions.Add(png);
        Ui.Add(exportBar, Ui.Actions(pdfAction, png, Ui.Button("Export STL…", SaveStl)), 0);
    }

    private void PrintControls(Panel panel)
    {
        Ui.Number(panel, "Resolution", current.Dpi, 72, 1200, x => Changed(() => current.Dpi = (int)x), false, whole: true, unit: "dpi");
        Ui.Number(panel, "Bleed per edge", current.Bleed, 0, 10, x => Changed(() => current.Bleed = x), false, unit: "mm");
    }

    private void RestoreArtworkFocus()
    {
        if (artworkList?.SelectedItem is ListBoxItem selected)
        {
            selected.BringIntoView();
            selected.Focus();
        }
    }

    private void Changed(Action change)
    {
        change();
        RequestProof();
    }

    private void Frame(Func<Artwork, Artwork> edit)
    {
        if (current.SelectedArtwork is { } artwork)
            current.Artwork[current.Selected] = edit(artwork);
        RequestProof();
    }

    private int MaximumCopies(Artwork image) => PrintLayout.MaxCopies - current.Artwork.Sum(a => a.Copies) + image.Copies;

    private void AddImages()
    {
        var dialog = new OpenFileDialog { Title = "Add artwork to the sheet", Filter = ImageFilter, Multiselect = true };
        if (dialog.ShowDialog(this) != true)
            return;
        var successes = 0;
        var errors = new List<string>();
        foreach (var file in dialog.FileNames)
        {
            try
            {
                AddImage(file);
                successes++;
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidDataException or ArgumentException)
            {
                errors.Add($"{Path.GetFileName(file)} · {error.Message}");
            }
            if (current.Artwork.Sum(a => a.Copies) == PrintLayout.MaxCopies)
            {
                if (successes + errors.Count < dialog.FileNames.Length)
                    errors.Add("The sheet is limited to 24 labels.");
                break;
            }
        }
        RebuildInspector();
        string summary = successes > 0 ? $"Added {successes} {(successes == 1 ? "image" : "images")}. " : "";
        SetStatus((summary + string.Join(" ", errors.Take(2))).Trim(), error: errors.Count > 0);
    }

    private string SampleDirectory() => Path.Combine(ResourcesDirectory, "Samples", current.Profile.Id);

    private void ShowSamples(Button anchor)
    {
        var directory = SampleDirectory();
        if (!Directory.Exists(directory))
        {
            LoadSample();
            return;
        }
        var menu = new ContextMenu { PlacementTarget = anchor, Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom };
        foreach (var path in Directory.EnumerateFiles(directory, "*.png").OrderBy(Path.GetFileName, StringComparer.Ordinal))
        {
            var item = new MenuItem { Header = Path.GetFileNameWithoutExtension(path) };
            item.Click += (_, _) => ImportSample(path);
            menu.Items.Add(item);
        }
        anchor.ContextMenu = menu;
        menu.IsOpen = true;
    }

    private void LoadSample()
    {
        if (current.Profile.SampleArtwork is not { } name)
            return;
        var direct = Path.Combine(SampleDirectory(), name);
        var path = File.Exists(direct) ? direct : Directory.EnumerateFiles(
            Path.Combine(ResourcesDirectory, "Samples"), "*.png", SearchOption.AllDirectories)
            .FirstOrDefault(file => Path.GetFileName(file).Equals(name, StringComparison.OrdinalIgnoreCase));
        if (path is null)
        {
            SetStatus($"The sample {name} is unavailable.", error: true);
            return;
        }
        ImportSample(path);
    }

    private void ImportSample(string path) => Run(() =>
    {
        AddImage(path);
        RebuildInspector();
        SetStatus($"Added {Path.GetFileNameWithoutExtension(path)}.");
    });

    private void AddImage(string path)
    {
        CheckRoom();
        var bitmap = PrintLayout.ReadBitmap(path);
        current.Artwork.Add(new(Path.GetFileNameWithoutExtension(path), bitmap));
        current.Selected = current.Artwork.Count - 1;
    }

    private void CheckRoom()
    {
        if (current.Artwork.Sum(a => a.Copies) >= PrintLayout.MaxCopies)
            throw new InvalidDataException("The sheet is limited to 24 labels.");
    }

    private void RemoveSelected()
    {
        if (current.SelectedArtwork is not { } image)
            return;
        current.Artwork.RemoveAt(current.Selected);
        image.Bitmap.Dispose();
        current.Selected = Math.Max(0, Math.Min(current.Selected, current.Artwork.Count - 1));
        RebuildInspector();
    }

    private void ValidatePrint()
    {
        if (!current.HasValidTrim)
            throw new InvalidDataException("Adjust the custom trim so its dimensions, radius and chamfer fit.");
        if (!current.Settings.CanRasterize)
            throw new InvalidDataException("The artwork is too large for this resolution. Lower the dpi.");
    }

    private void SavePng() => Run(() =>
    {
        ValidatePrint();
        if (current.SelectedArtwork is not { } art)
            return;
        Save("PNG image", "png", $"{current.Profile.ExportPrefix}-vinyl", stream =>
        {
            using var image = PrintLayout.Rasterize(current.Settings, art);
            PrintLayout.WritePng(stream, image, current.Dpi);
        });
    });

    private void SavePdf() => Run(() =>
    {
        ValidatePrint();
        if (PrintLayout.Layout(current.Settings, current.Artwork).Length == 0)
            throw new InvalidDataException("Add artwork that fits on A4 and use up to 24 copies.");
        Save("A4 PDF", "pdf", $"{current.Profile.ExportPrefix}-a4",
            stream => PrintLayout.WritePdf(stream, current.Settings, current.Artwork));
    });

    private void SaveStl() => Run(() =>
        Save("STL model", "stl", $"cartrest-{current.Profile.Id}-{current.Width:0.###}mm",
            stream => current.Model.WriteStl(stream, current.Width)));

    private void Save(string name, string extension, string stem, Action<Stream> write)
    {
        var dialog = new SaveFileDialog
        {
            Title = $"Save {name}", FileName = stem, DefaultExt = $".{extension}",
            Filter = $"{name} (*.{extension})|*.{extension}", AddExtension = true
        };
        if (dialog.ShowDialog(this) != true)
            return;
        WriteFile(dialog.FileName, write);
        SetStatus($"Saved {Path.GetFileName(dialog.FileName)}.");
    }

    internal static void WriteFile(string destination, Action<Stream> write)
    {
        string directory = Path.GetDirectoryName(destination) ?? throw new IOException("Choose an output folder.");
        string temporary = Path.Combine(directory, $".cartrest-{Guid.NewGuid():N}.tmp");
        try
        {
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write))
                write(file);
            File.Move(temporary, destination, overwrite: true);
        }
        finally
        {
            File.Delete(temporary);
        }
    }
}
