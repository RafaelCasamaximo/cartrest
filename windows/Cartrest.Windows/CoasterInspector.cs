using System.IO;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using Cartrest.Core;
using Microsoft.Win32;

namespace Cartrest.Windows;

internal sealed partial class MainWindow
{
    private void BuildCoasterInspector()
    {
        var artwork = Ui.Section(tools, "Artwork");
        var actions = Ui.Row(Ui.Button("Add images…", AddImages, prominent: true), Ui.Button("Load sample", LoadSample));
        actions.Children[1].IsEnabled = current.Profile.SampleArtwork is not null;
        Ui.Add(artwork, actions);
        if (current.Artwork.Count > 0)
        {
            var list = new ListBox
            {
                MaxHeight = 135,
                MinHeight = 32,
                Background = Ui.Input,
                Foreground = Ui.Text,
                BorderBrush = Ui.Edge
            };
            AutomationProperties.SetName(list, "Sheet artwork");
            foreach (var item in current.Artwork)
            {
                var line = Ui.Label(item.Name);
                line.ToolTip = item.Name;
                line.TextTrimming = TextTrimming.CharacterEllipsis;
                line.TextWrapping = TextWrapping.NoWrap;
                list.Items.Add(line);
            }
            list.SelectedIndex = current.Selected;
            list.SelectionChanged += (_, _) =>
            {
                if (list.SelectedIndex < 0 || list.SelectedIndex == current.Selected)
                    return;
                current.Selected = list.SelectedIndex;
                RebuildInspector();
            };
            Ui.Add(artwork, list, 6);
            if (current.SelectedArtwork is { } image)
            {
                Ui.Number(artwork, "Copies on sheet", image.Copies, 1, MaximumCopies(image), v =>
                    Frame(a => a with { Copies = (int)v }), slider: false, whole: true);
                Ui.Number(artwork, "Artwork zoom (%)", image.Zoom * 100, 100, 350, v => Frame(a => a with { Zoom = v / 100 }));
                Ui.Number(artwork, "Horizontal offset (%)", image.PanX * 100, -100, 100, v => Frame(a => a with { PanX = v / 100 }));
                Ui.Number(artwork, "Vertical offset (%)", image.PanY * 100, -100, 100, v => Frame(a => a with { PanY = v / 100 }));
                Ui.Add(artwork, Ui.Row(Ui.Button("Reset framing", () =>
                {
                    Frame(a => a with { Zoom = 1, PanX = 0, PanY = 0 });
                    RebuildInspector();
                }), Ui.Button("Remove", RemoveSelected)), 0);
            }
        }
        else
        {
            Ui.Add(artwork, Ui.Label("Add a label or cover image to start a sheet.", 12, Ui.Secondary), 0);
        }

        var size = Ui.Section(tools, "Coaster & trim");
        var range = current.Profile.WidthRange;
        Ui.Number(size, "Coaster width (mm)", current.Width, range.Min, range.Max, x => Changed(() => current.Width = x));
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

        var output = Ui.Section(tools, "Print & export");
        PrintControls(output);
        pdfAction = Ui.Button("Save A4 PDF…", SavePdf, prominent: true);
        var png = Ui.Button("Save PNG…", SavePng);
        pngActions.Add(png);
        Ui.Add(output, Ui.Row(pdfAction, png));
        Ui.Add(output, Ui.Button("Export STL…", SaveStl), 0);
    }

    private void PrintControls(Panel panel)
    {
        Ui.Number(panel, "Bleed per edge (mm)", current.Bleed, 0, 10, x => Changed(() => current.Bleed = x), false);
        Ui.Number(panel, "Resolution (dpi)", current.Dpi, 72, 1200, x => Changed(() => current.Dpi = (int)x), false, whole: true);
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

    private void LoadSample()
    {
        if (current.Profile.SampleArtwork is not { } name)
            return;
        Run(() =>
        {
            AddImage(Path.Combine(ResourcesDirectory, "Samples", name));
            RebuildInspector();
            SetStatus($"Added {name}.");
        });
    }

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
