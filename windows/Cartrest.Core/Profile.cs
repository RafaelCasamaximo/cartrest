using System.Diagnostics.CodeAnalysis;

using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using SkiaSharp;

namespace Cartrest.Core;

public sealed record WidthRange(double Min, double Max);
public sealed record Tint(string Color, double Strength);
public sealed record Mat(string Highlight, string Center, string Shadow, Tint? Tint, string Direction = "diagonal", double GridOpacity = 1);
public sealed record Shell(string Highlight, string Shadow);
public sealed record Palette(Mat Mat, string Grid, Shell Shell, string Plastic, string Recess);
public sealed record Radii(double TopLeft, double TopRight, double BottomRight, double BottomLeft)
{
    public static Radii Uniform(double radius) => new(radius, radius, radius, radius);
}
public readonly record struct Point2(double X, double Y);
public sealed record Body(double Width, double Height, double Thickness, Radii CornerRadii, Point2[]? Vertices);
public sealed record Region(double X, double Y, double Width, double Height, double Radius, double Chamfer, double Depth = 0)
{
    public SKRect Rect => new((float)X, (float)Y, (float)(X + Width), (float)(Y + Height));
    public Region Scale(double factor) => new(X * factor, Y * factor, Width * factor, Height * factor, Radius * factor, Chamfer * factor, Depth * factor);
}
public sealed record Arrow(double CenterX, double Top, double Width, double Height, double Depth);
public sealed record Geometry(string Unit, Body Body, Region Recess, Region Label, Arrow? Arrow, Region? Grip);
public sealed record Instruction(string Op, double X, double Y, int Count, double Width, double Height, double Pitch, double Radius, double Chamfer, double Depth);

public sealed partial record Profile(int SchemaVersion, string Id, string Name, int Order, WidthRange WidthRange, Palette Palette,
    string? ArtworkFilePrefix, string? SampleArtwork, string? LabelTemplate, Geometry Geometry, Instruction[] Instructions)
{
    internal static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        RespectNullableAnnotations = true,
        MaxDepth = 32
    };

    public double Scale(double width)
    {
        Require(width >= WidthRange.Min && width <= WidthRange.Max, $"Choose a width from {WidthRange.Min:g} to {WidthRange.Max:g} mm.");
        return width / Geometry.Body.Width;
    }

    public string ExportPrefix => ArtworkFilePrefix ?? $"cartrest-{Id}";

    public Region LabelAt(double width) => Geometry.Label.Scale(Scale(width));

    public static Profile Load(string path)
    {
        using var file = File.OpenRead(path);
        Require(file.Length <= 256 * 1024, "Choose a profile no larger than 256 KiB.");
        var profile = JsonSerializer.Deserialize<Profile>(file, JsonOptions)
            ?? throw new InvalidDataException("The profile is empty.");
        profile.Validate();
        return profile;
    }

    private void Validate()
    {
        Require(SchemaVersion == 1, "Use profile schema version 1.");
        Require(ValidId(Id) && (ArtworkFilePrefix is null || ValidId(ArtworkFilePrefix)) && (LabelTemplate is null || ValidId(LabelTemplate)), "Use up to 64 lowercase letters, digits and single hyphens for IDs and file prefixes.");
        Require(!string.IsNullOrWhiteSpace(Name) && Name.Length <= 64 && !Name.Any(char.IsControl), "Use a console name from 1 to 64 characters.");
        Require(SampleArtwork is null || (SampleArtwork.Length is > 0 and <= 128 && !SampleArtwork.StartsWith('.') && !SampleArtwork.Any(char.IsControl) && !SampleArtwork.Contains('/') &&
            !SampleArtwork.Contains('\\') && Path.GetFileName(SampleArtwork) == SampleArtwork), "Use a file name for sampleArtwork.");
        Require(Geometry?.Body?.CornerRadii is not null && WidthRange is not null, "Supply geometry and a width range.");
        var body = Geometry!.Body;
        Require(Geometry.Unit == "mm" && WidthRange!.Min >= 10 && WidthRange.Min <= body.Width &&
            body.Width <= WidthRange.Max && WidthRange.Max <= 500 && body.Height is >= 0.01 and <= 1000 &&
            body.Thickness is >= 0.01 and <= 100, "Use millimeters and a 10–500 mm width range containing the nominal width.");
        var radii = body.CornerRadii;
        Require(new[] { radii.TopLeft, radii.TopRight, radii.BottomRight, radii.BottomLeft }.All(r => r >= 0 && r <= Math.Min(body.Width, body.Height) / 2),
            "Body corner radii must fit within half the shorter side.");
        Require(body.Vertices is null || body.Vertices.Length is >= 3 and <= 256, "Supply 3–256 custom outline vertices.");
        ValidateRegion(Geometry.Recess, body, "label recess", cut: true);
        ValidateRegion(Geometry.Label, body, "label");
        if (Geometry.Grip is { } grip)
            ValidateRegion(grip, body, "grip", cut: true);
        if (Geometry.Arrow is { } a)
            ValidateRegion(new(a.CenterX - a.Width / 2, a.Top, a.Width, a.Height, 0, 0, a.Depth), body, "arrow", cut: true);
        Require(Palette?.Mat is not null && Palette.Shell is not null, "Supply the mat and shell palette.");
        var mat = Palette!.Mat;
        foreach (var color in new[] { mat.Highlight, mat.Center, mat.Shadow, Palette.Grid, Palette.Shell.Highlight,
            Palette.Shell.Shadow, Palette.Plastic, Palette.Recess, mat.Tint?.Color ?? "#000000" })
            Require(color is { Length: 7 } && color.StartsWith('#') && SKColor.TryParse(color, out _), "Use #RRGGBB palette colors.");
        Require(mat.Direction is "diagonal" or "horizontal" or "vertical" or "reverseDiagonal" &&
            mat.GridOpacity is >= 0 and <= 1 && (mat.Tint is null || mat.Tint.Strength is >= 0 and <= 1),
            "Supply a supported gradient direction and use opacity or tint strengths from 0 to 1.");
        Require(Instructions is { Length: >= 2 and <= 67 } && Instructions[0]?.Op == "extrudeBody",
            "Start the model recipe with extrudeBody and provide 2–67 instructions.");
    }

    internal static void ValidateRegion(Region region, Body body, string field, bool cut = false)
    {
        Require(region is not null, $"Supply the {field} region.");
        var shortSide = Math.Min(region!.Width, region.Height);
        Require(region.X >= 0 && region.Y >= 0 && shortSide > 0 && region.X + region.Width <= body.Width + 1e-7 &&
            region.Y + region.Height <= body.Height + 1e-7 && region.Radius >= 0 && region.Radius <= shortSide / 2 &&
            region.Chamfer >= 0 && region.Chamfer <= shortSide - region.Radius &&
            (!cut || (region.Depth > 0 && region.Depth < body.Thickness)), $"The {field} measurements must fit the cartridge.");
    }

    internal static void Require([DoesNotReturnIf(false)] bool condition, string message)
    {
        if (!condition)
            throw new InvalidDataException(message);
    }

    private static bool ValidId(string? value) => value is { Length: > 0 and <= 64 } && IdPattern().IsMatch(value);

    [GeneratedRegex(@"\A[a-z0-9]+(?:-[a-z0-9]+)*\z")]
    private static partial Regex IdPattern();
}
