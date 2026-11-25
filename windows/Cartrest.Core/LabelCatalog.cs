using System.Text.Json;
using SkiaSharp;

namespace Cartrest.Core;

public sealed record LabelAsset(string Id, string Name, string File)
{
    public override string ToString() => Name;
}

public sealed record RatingSystem(string Id, string Name, LabelAsset[] Marks)
{
    public override string ToString() => Name;
}

public sealed record LabelTemplate(string Id, string Name, string? Header, string? HeaderOnDark,
    string HeaderStyle, double HeaderHeight, string HeaderColor, string? HeaderLayout, double FooterHeight,
    string FooterColor, string CodeColor, string? CodeAlignment, string? CodeTypeface, string CodeExample, double MarkRow)
{
    public override string ToString() => Name;
}

public sealed record HeaderSegment(Point2 End, Point2[]? Controls);
public sealed record HeaderLayout(Point2 LogoCenter, double LogoWidth, double LogoHeight, HeaderSegment[] Seam);
public enum MarkRole { Rating, Publisher, Studio, Seal }
public enum HeaderStyle { Shadow, Flat, Hidden }
public enum CodeAlignment { Left, Center, Right }
public enum MarkBacking { None, Light, Dark }
public enum HalftoneMode { Off, Cmyk, Monochrome }

public sealed class LabelMark
{
    public string? AssetId { get; set; }
    public SKBitmap? Custom { get; set; }
    public double X { get; set; }
    public double Y { get; set; }
    public double Scale { get; set; } = 1;
    public MarkBacking Backing { get; set; }
}

public sealed class LabelDraft : IDisposable
{
    public LabelTemplate Template { get; private set; }
    public string Name { get; set; } = "";
    public string Title { get; set; } = "";
    public SKColor TitleColor { get; set; } = SKColors.White;
    public double TitlePosition { get; set; } = 0.46;
    public double TitleScale { get; set; } = 1;
    public SKBitmap? Background { get; set; }
    public SKColor BackgroundColor { get; set; } = new(35, 54, 47);
    public bool Fill { get; set; } = true;
    public double Zoom { get; set; } = 1;
    public double PanX { get; set; }
    public double PanY { get; set; }
    public HeaderStyle HeaderStyle { get; set; }
    public SKBitmap? HeaderLogo { get; set; }
    public SKColor HeaderColor { get; set; }
    public double HeaderHeight { get; set; } = 1;
    public double HeaderScale { get; set; } = 1;
    public string Code { get; set; } = "";
    public SKColor FooterColor { get; set; }
    public SKColor CodeColor { get; set; }
    public CodeAlignment CodeAlignment { get; set; }
    public double CodeScale { get; set; } = 1;
    public double Noise { get; set; }
    public double Grain { get; set; } = 0.2;
    public HalftoneMode Halftone { get; set; }
    public double HalftoneAmount { get; set; } = 0.25;
    public double DotSpacing { get; set; } = 0.35;
    public double Angle { get; set; } = 45;
    public LabelMark[] Marks { get; } = [new() { X = .13 }, new() { X = .38 }, new() { X = .64 }, new() { X = .87 }];

    public LabelDraft(LabelTemplate template)
    {
        Template = template;
        ResetTemplate(template);
        Code = template.CodeExample;
        foreach (var mark in Marks)
            mark.Y = template.MarkRow;
    }

    public void ResetTemplate(LabelTemplate template)
    {
        Template = template;
        HeaderStyle = Enum.Parse<HeaderStyle>(template.HeaderStyle, ignoreCase: true);
        HeaderColor = SKColor.Parse(template.HeaderColor);
        HeaderHeight = 1;
        HeaderScale = 1;
        FooterColor = SKColor.Parse(template.FooterColor);
        CodeColor = SKColor.Parse(template.CodeColor);
        CodeAlignment = Enum.TryParse<CodeAlignment>(template.CodeAlignment, true, out var alignment) ? alignment : CodeAlignment.Center;
        CodeScale = 1;
    }

    public void Dispose()
    {
        Background?.Dispose();
        HeaderLogo?.Dispose();
        foreach (var mark in Marks)
            mark.Custom?.Dispose();
    }
}

public sealed class LabelCatalog : IDisposable
{
    private sealed record Data(int SchemaVersion, LabelTemplate[] Templates, Dictionary<string, HeaderLayout> HeaderLayouts,
        LabelAsset[] Headers, RatingSystem[] RatingSystems, LabelAsset[] Companies, LabelAsset[] Seals);

    private readonly string root;
    private readonly Data data;
    private readonly Dictionary<string, LabelAsset> assets;
    private readonly Dictionary<string, SKBitmap> images = new(StringComparer.Ordinal);
    public IReadOnlyList<LabelTemplate> Templates => data.Templates;
    public IReadOnlyList<RatingSystem> Ratings => data.RatingSystems;
    public IReadOnlyList<LabelAsset> Companies => data.Companies;
    public IReadOnlyList<LabelAsset> Seals => data.Seals;
    public SKTypeface CodeTypeface { get; }
    public SKTypeface TitleTypeface { get; }
    public SKTypeface OcrTypeface { get; }

    public LabelCatalog(string path)
    {
        root = path;
        using var file = File.OpenRead(Path.Combine(root, "catalog.json"));
        data = JsonSerializer.Deserialize<Data>(file, Profile.JsonOptions)
            ?? throw new InvalidDataException("The label catalog is empty.");
        Profile.Require(data.SchemaVersion == 1, "The label catalog version is unsupported.");
        assets = data.Headers.Concat(data.RatingSystems.SelectMany(r => r.Marks))
            .Concat(data.Companies).Concat(data.Seals).ToDictionary(a => a.Id, StringComparer.Ordinal);
        CodeTypeface = SKTypeface.FromFamilyName("Consolas", SKFontStyle.Bold);
        TitleTypeface = SKTypeface.FromFamilyName("Segoe UI", SKFontStyle.Bold);
        OcrTypeface = SKTypeface.FromFile(Path.Combine(root, "fonts", "OCRB.otf")) ?? CodeTypeface;
    }

    public LabelTemplate Template(string? id) => Templates.FirstOrDefault(t => t.Id == id)
        ?? Templates.First(t => t.Id == "custom");

    public HeaderLayout? Layout(LabelTemplate template) => template.HeaderLayout is { } name
        ? data.HeaderLayouts.GetValueOrDefault(name) : null;

    public SKBitmap? Asset(string? id)
    {
        if (id is null || !assets.TryGetValue(id, out var asset))
            return null;
        if (!images.TryGetValue(id, out var bitmap))
        {
            bitmap = PrintLayout.ReadBitmap(Path.Combine(root, "assets", asset.File));
            images.Add(id, bitmap);
        }
        return bitmap;
    }

    public void Dispose()
    {
        foreach (var bitmap in images.Values)
            bitmap.Dispose();
        if (OcrTypeface != CodeTypeface)
            OcrTypeface.Dispose();
        TitleTypeface.Dispose();
        CodeTypeface.Dispose();
    }
}
