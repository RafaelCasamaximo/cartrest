using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Cartrest.Core;

namespace Cartrest.Windows;

internal sealed partial class MainWindow
{
    internal void VerifyInstalledApp(string output)
    {
        Require(workspaces.Select(w => w.Profile.Id).SequenceEqual(new[] { "ds", "3ds", "switch", "switch2" }), "The four stock profiles are missing.");
        Require(tabs.Count == 4 && current.Mode == ProofMode.Coaster, "The native console controls did not load.");
        Require(toolbarMark.Source is BitmapSource { PixelWidth: >= 256, PixelHeight: >= 256 },
            "The high-resolution toolbar mark is missing.");
        Screenshot("empty");
        LoadSample();
        Require(current.SelectedArtwork?.Name == "Mario Kart DS", "The retail artwork sample was not imported.");
        UpdateProof();
        Screenshot("coaster");
        SetMode(ProofMode.ThreeD);
        Screenshot("cartridge-front");
        var original = orbit.Orientation;
        orbit.TurnForTesting();
        Require(orbit.Orientation != original, "The 3D workspace did not rotate.");
        Screenshot("cartridge-back");

        ShowDesigner(true);
        LoadKirbyStudy();
        Require(current.Draft.Name == "Kirby Super Star Ultra", "The Kirby study did not load.");
        UpdateProof();
        SetDesignerPane(DesignerPane.Effects);
        Screenshot("label-designer");
        SetDesignerPane(DesignerPane.HeaderAndCode);
        Screenshot("label-header");
        SetDesignerPane(DesignerPane.Marks);
        Require(designerPane == DesignerPane.Marks && current.Draft.Code == "NTR-YKWE-USA", "Switching designer sections lost the label.");
        SetDesignerPane(DesignerPane.Artwork);
        Require(catalog.Asset("studio-nintendo-outline") is not null && catalog.Asset("studio-hal-inutamago") is not null,
            "The Kirby marks were not bundled.");
        using (var label = LabelRenderer.Render(current.Draft, catalog, current.Settings))
        {
            Require(label.Width == 1013 && label.Height == 1068, "The printed label dimensions are wrong.");
            WriteFile(Path.Combine(output, "kirby-label.png"), stream => PrintLayout.WritePng(stream, label, current.Dpi));
        }
        AddDesignedLabel();
        Require(!designer && current.Mode == ProofMode.Sheet && current.Artwork.Count == 2, "Add to Sheet did not transfer the drafted label.");
        Require(PrintLayout.Layout(current.Settings, current.Artwork) is [var first] && first.Length == 2, "Two distinct labels did not fit on the first A4 page.");
        WriteFile(Path.Combine(output, "labels-a4.pdf"), stream => PrintLayout.WritePdf(stream, current.Settings, current.Artwork));
        Screenshot("a4-sheet");

        current.Width = 120;
        WriteFile(Path.Combine(output, "cartrest-ds-120mm.stl"), stream => current.Model.WriteStl(stream, current.Width));
        SetMode(ProofMode.Cut);
        Require(Math.Abs(current.Settings.Label.Width - 98.16) < .001, "The trim did not follow the width.");
        Screenshot("cut");
        Appearance.Apply(Application.Current, dark: false);
        SetMode(ProofMode.Coaster);
        Width = MinWidth;
        Screenshot("coaster-light");
        Screenshot("coaster-hidpi", 2);
        Select(workspaces.Single(w => w.Profile.Id == "switch2"));
        LoadSample();
        UpdateProof();
        Screenshot("switch2-light");
        File.WriteAllText(Path.Combine(output, "passed.txt"), "Installed Windows app verified.\n");

        void Screenshot(string name, int density = 1)
        {
            UpdateLayout();
            var source = (Visual)Content;
            int width = (int)((System.Windows.FrameworkElement)Content).ActualWidth;
            int height = (int)((System.Windows.FrameworkElement)Content).ActualHeight;
            var screenshot = new RenderTargetBitmap(width * density, height * density, 96 * density, 96 * density, PixelFormats.Pbgra32);
            screenshot.Render(source);
            WriteFile(Path.Combine(output, $"{name}.png"), stream =>
            {
                var encoder = new PngBitmapEncoder();
                encoder.Frames.Add(BitmapFrame.Create(screenshot));
                encoder.Save(stream);
            });
        }
    }

    private static void Require(bool result, string error)
    {
        if (!result)
            throw new InvalidDataException(error);
    }
}
