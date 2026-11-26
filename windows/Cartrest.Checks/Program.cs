using System.Buffers.Binary;
using System.Numerics;
using System.Text;
using Cartrest.Core;
using SkiaSharp;

string root = Path.GetFullPath(args.FirstOrDefault() ?? ".");
string output = args.Length > 1 ? Path.GetFullPath(args[1]) : Path.Combine(Path.GetTempPath(), "cartrest-checks");
Directory.CreateDirectory(output);
var profiles = new[] { "ds", "3ds", "switch", "switch2" };
foreach (var id in profiles)
{
    var profile = Profile.Load(Path.Combine(root, "consoles", id + ".json"));
    var mesh = CartridgeMesh.Build(profile);
    foreach (double width in new[] { profile.WidthRange.Min, profile.Geometry.Body.Width, profile.WidthRange.Max })
    {
        ValidateStl(mesh, width, profile);
        ValidateHolderStl(profile, width, CoasterHolder.MinimumSlots, CoasterHolder.MinimumClearance);
        ValidateHolderStl(profile, width, CoasterHolder.DefaultSlots, CoasterHolder.DefaultClearance);
        ValidateHolderStl(profile, width, CoasterHolder.MaximumSlots, CoasterHolder.MaximumClearance);
    }
    // Compare the app mesh with the shipped reference at nominal scale.
    string reference = Path.Combine(root, "model", id == "ds" ? "" : id, $"cartrest-{id}-100mm.stl");
    using var nominal = new MemoryStream();
    mesh.WriteStl(nominal, 100);
    var a = MeasureStl(nominal);
    using var original = File.OpenRead(reference);
    var b = MeasureStl(original);
    Require(Math.Abs(a.Volume - b.Volume) / b.Volume < 0.00002, $"{id} mesh volume differs from the reference.");
    Require(a.Size == b.Size, $"{id} mesh bounds differ from the reference.");
    Console.WriteLine($"{id}: closed coaster and holder meshes at all test widths, {a.Count} coaster triangles, reference volume matched.");
}

string graph = Path.Combine(root, "examples", "profiles", "ds-graphite.json");
if (File.Exists(graph))
{
    var example = Profile.Load(graph);
    ValidateStl(CartridgeMesh.Build(example), 100, example);
}

var ds = Profile.Load(Path.Combine(root, "consoles", "ds.json"));
var settings = new PrintSettings(ds.LabelAt(100));
using var source = PrintLayout.ReadBitmap(Path.Combine(root, "examples", "cartridge-labels", "Kirby Super Star Ultra.png"));
var artwork = new Artwork("Kirby Super Star Ultra", source, Copies: 5);
var layout = PrintLayout.Layout(settings, [artwork]);
Require(layout.Length == 2 && layout[0].Length == 4 && layout[1].Length == 1, "A4 pagination is incorrect.");
Require(Math.Abs(layout[0][0].Area.Width - 85.8) < .001 && Math.Abs(layout[0][2].Area.Top - 126.4) < .001, "A4 size or gap is incorrect.");
Require(PrintLayout.Layout(settings, [artwork with { Copies = 25 }]).Length == 0, "The copy limit was ignored.");
using var raster = PrintLayout.Rasterize(settings, artwork);
Require(raster.Width == 1013 && raster.Height == 1068, "Raster dimensions are incorrect.");
using (var png = new MemoryStream())
{
    PrintLayout.WritePng(png, raster, 300);
    byte[] data = png.ToArray();
    Require(data.AsSpan(37, 4).SequenceEqual("pHYs"u8) &&
        BinaryPrimitives.ReadUInt32BigEndian(data.AsSpan(41, 4)) == 11811 && data[49] == 1, "PNG print resolution is missing.");
    File.WriteAllBytes(Path.Combine(output, "raster.png"), data);
}
using (var pdf = File.Create(Path.Combine(output, "sheet-a4.pdf")))
    PrintLayout.WritePdf(pdf, settings, [artwork]);
using var catalog = new LabelCatalog(Path.Combine(root, "design", "labels"));
Require(catalog.Templates.Count == 9 && catalog.Ratings.Count == 9, "The label catalog is incomplete.");
foreach (var template in catalog.Templates)
{
    using var draft = new LabelDraft(template);
    using var bitmap = LabelRenderer.Render(draft, catalog, settings, previewLimit: 420);
    Require(bitmap.Width > 0 && bitmap.Height == 420, "A label template failed to render.");
}

using (var draft = new LabelDraft(catalog.Template("ds")) { Background = source.Copy(), HeaderColor = SKColors.White, FooterColor = SKColors.White })
{
    draft.Marks[0].AssetId = "esrb-e-legacy";
    using var plain = LabelRenderer.Render(draft, catalog, settings);
    draft.Noise = .05;
    draft.Halftone = HalftoneMode.Cmyk;
    draft.HalftoneAmount = .13;
    using var screen = LabelRenderer.Render(draft, catalog, settings);
    using var repeat = LabelRenderer.Render(draft, catalog, settings);
    Require(!screen.Pixels.SequenceEqual(plain.Pixels) && screen.Pixels.SequenceEqual(repeat.Pixels),
        "Effects did not change the artwork deterministically.");
    Require(screen.GetPixel(10, 10) == SKColors.White && screen.GetPixel(10, screen.Height - 10) == SKColors.White,
        "Effects altered the white header or footer.");
    using var file = File.Create(Path.Combine(output, "designer.png"));
    PrintLayout.WritePng(file, screen, 300);
}
Console.WriteLine("Print geometry, raster resolution, pagination, templates and effects verified.");

static void ValidateStl(CartridgeMesh mesh, double width, Profile profile)
{
    using var stream = new MemoryStream();
    mesh.WriteStl(stream, width);
    var measured = MeasureStl(stream);
    var body = profile.Geometry.Body;
    var scale = profile.Scale(width);
    Require(Math.Abs(measured.Size.X - width) < .001 && Math.Abs(measured.Size.Y - body.Height * scale) < .001 &&
        Math.Abs(measured.Size.Z - body.Thickness * scale) < .001, $"The {profile.Id} STL did not scale all three axes.");
}

static void ValidateHolderStl(Profile profile, double width, int slots, double clearance)
{
    var holder = new CoasterHolder(profile, width, slots, clearance);
    var body = profile.Geometry.Body;
    double scale = profile.Scale(width);
    // The 3DS tab sits above the guides and should contribute nothing to slot width.
    double lowerWidth = profile.Id == "3ds" ? 94.5559 : body.Width;
    Require(Math.Abs(holder.SlotWidth - lowerWidth * scale - 2 * clearance) < .001 &&
        Math.Abs(holder.SlotDepth - body.Thickness * scale - 2 * clearance) < .001,
        $"The {profile.Id} slot did not fit the lower outline and scaled thickness.");
    double endFoot = Math.Max(10, body.Height * scale * 0.14);
    double depth = 2 * endFoot + (slots + 1) * 4 + slots * holder.SlotDepth;

    using var stream = new MemoryStream();
    holder.WriteStl(stream);
    var (size, volume, _) = MeasureStl(stream);
    Require(Math.Abs(size.X - holder.Width) < .001 && Math.Abs(size.Y - depth) < .001 &&
        Math.Abs(size.Z - holder.Height) < .001 && volume > 0,
        $"The {profile.Id} holder failed to export one rack with {slots} slots at {width:g} mm.");
}

static (Vector3 Size, double Volume, uint Count) MeasureStl(Stream stream)
{
    stream.Position = 80;
    using var reader = new BinaryReader(stream, Encoding.ASCII, leaveOpen: true);
    uint count = reader.ReadUInt32();
    Require(stream.Length == 84 + count * 50, "STL length disagrees with its triangle count.");
    var min = new Vector3(float.PositiveInfinity);
    var max = new Vector3(float.NegativeInfinity);
    double volume = 0;
    for (int i = 0; i < count; i++)
    {
        stream.Position += 12;
        var a = ReadVertex();
        var b = ReadVertex();
        var c = ReadVertex();
        stream.Position += 2;
        volume += Vector3.Dot(a, Vector3.Cross(b - a, c - a)) / 6d;
    }
    return (max - min, volume, count);

    Vector3 ReadVertex()
    {
        var v = new Vector3(reader.ReadSingle(), reader.ReadSingle(), reader.ReadSingle());
        min = Vector3.Min(min, v);
        max = Vector3.Max(max, v);
        return v;
    }
}

static void Require(bool condition, string message)
{
    if (!condition)
        throw new InvalidDataException(message);
}
