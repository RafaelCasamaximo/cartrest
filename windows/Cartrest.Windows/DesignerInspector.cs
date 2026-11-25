using System.IO;
using System.Windows.Controls;
using Cartrest.Core;
using Microsoft.Win32;
using SkiaSharp;

namespace Cartrest.Windows;

internal sealed partial class MainWindow
{
    private sealed record AssetChoice(string? Id, string Name)
    {
        public override string ToString() => Name;
    }

    private void BuildDesignerInspector()
    {
        var draft = current.Draft;
        sheetAction = Ui.Button("Add to Sheet", AddDesignedLabel, prominent: true);
        var png = Ui.Button("Save PNG…", SaveDesignedPng);
        pngActions.Add(png);
        Ui.Add(exportBar, Ui.Actions(png, sheetAction), 0);

        switch (designerPane)
        {
            case DesignerPane.Artwork: DesignArtwork(draft); break;
            case DesignerPane.Effects: DesignEffects(draft); break;
            case DesignerPane.HeaderAndCode: DesignHeader(draft); break;
            case DesignerPane.Marks: DesignMarks(draft); break;
        }
    }

    private void DesignArtwork(LabelDraft draft)
    {
        var art = Ui.Section(tools, "Artwork");
        Ui.TextField(art, "Artwork name", draft.Name, x => draft.Name = x);
        var images = Ui.Actions(Ui.Button(draft.Background is null ? "Import image…" : "Replace image…", ImportBackground));
        if (draft.Background is not null)
            images.Children.Add(Ui.Button("Clear image", () =>
            {
                draft.Background.Dispose();
                draft.Background = null;
                RebuildInspector();
            }));
        Ui.Add(art, images);
        if (current.Profile.Id == "ds")
            Ui.Add(art, Ui.Button("Load Kirby study", LoadKirbyStudy));
        Ui.ColorField(art, "Background color", draft.BackgroundColor, x => Changed(() => draft.BackgroundColor = x));
        Ui.Choice(art, "Image fit", new[] { "Fill", "Fit" }, draft.Fill ? "Fill" : "Fit", x => Changed(() => draft.Fill = x == "Fill"));
        if (draft.Background is not null)
        {
            Ui.Number(art, "Zoom", draft.Zoom * 100, 100, 350, x => Changed(() => draft.Zoom = x / 100), unit: "%");
            Ui.Number(art, "Horizontal", draft.PanX * 100, -100, 100, x => Changed(() => draft.PanX = x / 100), unit: "%");
            Ui.Number(art, "Vertical", draft.PanY * 100, -100, 100, x => Changed(() => draft.PanY = x / 100), unit: "%");
        }
        var title = Ui.Section(tools, "Title");
        Ui.TextField(title, "Optional title", draft.Title, x => Changed(() => draft.Title = x));
        Ui.ColorField(title, "Title color", draft.TitleColor, x => Changed(() => draft.TitleColor = x));
        Ui.Number(title, "Title size", draft.TitleScale * 100, 50, 185, x => Changed(() => draft.TitleScale = x / 100), unit: "%");
        Ui.Number(title, "Title position", draft.TitlePosition * 100, 20, 85, x => Changed(() => draft.TitlePosition = x / 100), unit: "%");
        PrintControls(Ui.Section(tools, "Printing"));
    }

    private void DesignHeader(LabelDraft draft)
    {
        var graphics = Ui.Section(tools, "Header");
        Ui.Choice(graphics, "Label template", catalog.Templates, draft.Template, template =>
        {
            if (template == draft.Template)
                return;
            bool replaceCode = string.IsNullOrWhiteSpace(draft.Code) || draft.Code == draft.Template.CodeExample;
            draft.ResetTemplate(template);
            if (replaceCode)
                draft.Code = template.CodeExample;
            RebuildInspector();
        });
        Ui.Choice(graphics, "Header style", Enum.GetValues<HeaderStyle>(), draft.HeaderStyle, x =>
        {
            draft.HeaderStyle = x;
            RebuildInspector();
        });
        if (draft.HeaderStyle != HeaderStyle.Hidden)
        {
            var logos = Ui.Actions(Ui.Button(draft.HeaderLogo is null ? "Import logo…" : "Replace logo…", () =>
                ImportDesignerImage("Choose a header logo", image =>
                {
                    draft.HeaderLogo?.Dispose();
                    draft.HeaderLogo = image;
                })));
            if (draft.HeaderLogo is not null)
                logos.Children.Add(Ui.Button("Use template logo", () =>
                {
                    draft.HeaderLogo.Dispose();
                    draft.HeaderLogo = null;
                    RebuildInspector();
                }));
            Ui.Add(graphics, logos);
            Ui.ColorField(graphics, "Band color", draft.HeaderColor, v => Changed(() => draft.HeaderColor = v));
            Ui.Number(graphics, "Band height", draft.HeaderHeight * 100, 50, 150, v => Changed(() => draft.HeaderHeight = v / 100), unit: "%");
            Ui.Number(graphics, "Logo size", draft.HeaderScale * 100, 50, 150, v => Changed(() => draft.HeaderScale = v / 100), unit: "%");
        }
        var code = Ui.Section(tools, "Product code");
        Ui.TextField(code, "Code", draft.Code, v => Changed(() => draft.Code = v));
        Ui.Choice(code, "Code alignment", Enum.GetValues<CodeAlignment>(), draft.CodeAlignment,
            v => Changed(() => draft.CodeAlignment = v));
        Ui.ColorField(code, "Code color", draft.CodeColor, v => Changed(() => draft.CodeColor = v));
        Ui.ColorField(code, "Footer color", draft.FooterColor, v => Changed(() => draft.FooterColor = v));
        Ui.Number(code, "Code size", draft.CodeScale * 100, 45, 155, v => Changed(() => draft.CodeScale = v / 100), unit: "%");
    }

    private void DesignMarks(LabelDraft draft)
    {
        var marks = Ui.Section(tools, "Ratings & logos");
        Ui.Choice(marks, "Mark slot", Enum.GetValues<MarkRole>(), markRole, role =>
        {
            markRole = role;
            RebuildInspector();
        });
        var item = draft.Marks[(int)markRole];
        IEnumerable<LabelAsset> choices;
        if (markRole == MarkRole.Rating)
        {
            ratingSystem ??= catalog.Ratings.FirstOrDefault(system => system.Marks.Any(a => a.Id == item.AssetId)) ?? catalog.Ratings[0];
            Ui.Choice(marks, "Rating system", catalog.Ratings, ratingSystem, system =>
            {
                ratingSystem = system;
                RebuildInspector();
            });
            choices = ratingSystem.Marks;
        }
        else
        {
            choices = markRole == MarkRole.Seal ? catalog.Seals : catalog.Companies;
        }
        var items = choices.Select(a => new AssetChoice(a.Id, a.Name)).Prepend(new AssetChoice(null, "None")).ToArray();
        Ui.Choice(marks, "Graphic", items, items.FirstOrDefault(x => x.Id == item.AssetId) ?? items[0], option =>
        {
            item.AssetId = option.Id;
            item.Custom?.Dispose();
            item.Custom = null;
            RebuildInspector();
        });
        var uploads = Ui.Actions(Ui.Button(item.Custom is null ? "Import mark…" : "Replace mark…", () =>
            ImportDesignerImage("Choose a rating or company mark", image =>
            {
                item.Custom?.Dispose();
                item.Custom = image;
            })));
        if (item.Custom is not null)
            uploads.Children.Add(Ui.Button("Clear custom", () =>
            {
                item.Custom.Dispose();
                item.Custom = null;
                RebuildInspector();
            }));
        Ui.Add(marks, uploads);
        Ui.Number(marks, "Horizontal", item.X * 100, 0, 100, v => Changed(() => item.X = v / 100), unit: "%");
        Ui.Number(marks, "Vertical", item.Y * 100, 0, 100, v => Changed(() => item.Y = v / 100), unit: "%");
        Ui.Number(marks, "Size", item.Scale * 100, 35, 190, v => Changed(() => item.Scale = v / 100), unit: "%");
        Ui.Choice(marks, "Backing", Enum.GetValues<MarkBacking>(), item.Backing, v => Changed(() => item.Backing = v));

    }

    private void DesignEffects(LabelDraft draft)
    {
        var noise = Ui.Section(tools, "Noise");
        Ui.Number(noise, "Noise amount", draft.Noise * 100, 0, 100, x => Changed(() => draft.Noise = x / 100), unit: "%");
        Ui.Number(noise, "Grain size", draft.Grain, 0.05, 1.2, x => Changed(() => draft.Grain = x), unit: "mm");

        var effects = Ui.Section(tools, "Halftone");
        var styles = Enum.GetValues<HalftoneMode>();
        var screens = new SegmentBar<HalftoneMode>("Halftone screen", value => value == HalftoneMode.Cmyk ? "CMYK" : value.ToString(),
            value => Changed(() => draft.Halftone = value), expanded: true);
        screens.Load(styles, draft.Halftone);
        Ui.Add(effects, screens, 8);
        Ui.Number(effects, "Halftone amount", draft.HalftoneAmount * 100, 0, 100, x => Changed(() => draft.HalftoneAmount = x / 100), unit: "%");
        Ui.Number(effects, "Dot spacing", draft.DotSpacing, 0.15, 2, x => Changed(() => draft.DotSpacing = x), unit: "mm");
        Ui.Number(effects, "Screen angle", draft.Angle, 0, 180, x => Changed(() => draft.Angle = x), unit: "°");
    }

    private void ImportBackground() => ImportDesignerImage("Choose a label background", image =>
    {
        var draft = current.Draft;
        draft.Background?.Dispose();
        draft.Background = image;
    });

    private void ImportDesignerImage(string title, Action<SKBitmap> setImage)
    {
        var picker = new OpenFileDialog { Title = title, Filter = ImageFilter };
        if (picker.ShowDialog(this) != true)
            return;
        Run(() =>
        {
            setImage(PrintLayout.ReadBitmap(picker.FileName));
            RebuildInspector();
        });
    }

    private void LoadKirbyStudy() => Run(() =>
    {
        LoadKirby();
        RebuildInspector();
        SetStatus("Loaded the Kirby Super Star Ultra reconstruction.");
    });

    private void LoadKirby()
    {
        var draft = current.Draft;
        var background = PrintLayout.ReadBitmap(Path.Combine(ResourcesDirectory, "Kirby", "background.png"));
        draft.Background?.Dispose();
        draft.Background = background;
        draft.HeaderLogo?.Dispose();
        draft.HeaderLogo = null;
        draft.ResetTemplate(catalog.Template("ds"));
        draft.Name = "Kirby Super Star Ultra";
        draft.Title = "";
        draft.Fill = true;
        draft.Zoom = 1;
        draft.PanX = draft.PanY = 0;
        draft.HeaderHeight = 0.91;
        draft.HeaderScale = 1.09;
        draft.HeaderColor = draft.FooterColor = SKColors.White;
        draft.Code = "NTR-YKWE-USA";
        draft.CodeAlignment = CodeAlignment.Right;
        draft.Noise = .05;
        draft.Grain = .20;
        draft.Halftone = HalftoneMode.Cmyk;
        draft.HalftoneAmount = .13;
        draft.DotSpacing = .35;
        draft.Angle = 45;
        var entries = new (string Id, double X, double Y, double Scale, MarkBacking Backing)[]
        {
            ("esrb-e-legacy", .137, .728, 1.20, MarkBacking.None),
            ("studio-nintendo-outline", .40, .827, .92, MarkBacking.None),
            ("studio-hal-inutamago", .358, .699, .72, MarkBacking.Light),
            ("seal-na", .823, .761, 1.40, MarkBacking.None)
        };
        for (int i = 0; i < entries.Length; i++)
        {
            var mark = draft.Marks[i];
            mark.Custom?.Dispose();
            mark.Custom = null;
            (mark.AssetId, mark.X, mark.Y, mark.Scale, mark.Backing) = entries[i];
        }
        ratingSystem = null;
    }

    private void AddDesignedLabel() => Run(() =>
    {
        ValidatePrint();
        CheckRoom();
        if (PrintLayout.PageCapacity(current.Settings) == 0)
            throw new InvalidDataException("Reduce the width or bleed so the label fits on A4.");
        var name = string.IsNullOrWhiteSpace(current.Draft.Name) ? $"{current.Profile.Name} label" : current.Draft.Name.Trim();
        current.Artwork.Add(new(name, LabelRenderer.Render(current.Draft, catalog, current.Settings)));
        current.Selected = current.Artwork.Count - 1;
        SetMode(ProofMode.Sheet);
        current.Page = Math.Max(0, PrintLayout.Layout(current.Settings, current.Artwork).Length - 1);
        RequestProof();
        SetStatus($"Added {name} to the sheet.");
    });

    private void SaveDesignedPng() => Run(() =>
    {
        ValidatePrint();
        Save("PNG image", "png", $"{current.Profile.ExportPrefix}-designed-label", stream =>
        {
            using var bitmap = LabelRenderer.Render(current.Draft, catalog, current.Settings);
            PrintLayout.WritePng(stream, bitmap, current.Dpi);
        });
    });
}
