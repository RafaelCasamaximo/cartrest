using System.Buffers.Binary;
using SkiaSharp;

namespace Cartrest.Core;

public sealed record PrintSettings(Region Label, double Bleed = 2, int Dpi = 300)
{
    public double Width => Label.Width + 2 * Bleed;
    public double Height => Label.Height + 2 * Bleed;
    public int PixelWidth => PrintLayout.Pixels(Width * Dpi / 25.4);
    public int PixelHeight => PrintLayout.Pixels(Height * Dpi / 25.4);

    public bool CanRasterize => Bleed is >= 0 and <= 10 && Dpi is >= 72 and <= 1200 &&
        PixelWidth > 0 && PixelHeight > 0 && (long)PixelWidth * PixelHeight <= PrintLayout.MaxPixels;

    public SKRect Trim => new((float)Bleed, (float)Bleed, (float)(Bleed + Label.Width), (float)(Bleed + Label.Height));
    public Region TrimRegion => Label with { X = Bleed, Y = Bleed };
}

public sealed record Artwork(string Name, SKBitmap Bitmap, int Copies = 1, double Zoom = 1, double PanX = 0, double PanY = 0);
public sealed record Placement(int ArtworkIndex, SKRect Area);

/// <summary>All sheet placements and cut dimensions are in millimeters until the PDF page transform.</summary>
public static class PrintLayout
{
    public const int MaxCopies = 24;
    public const int MaxPixels = 16_000_000;
    public const float PageWidth = 210;
    public const float PageHeight = 297;
    private const double Gap = 7;
    private const double Margin = 10;
    private const double GridTop = 29;
    private const double GridBottom = 266;
    private const float PointsPerMillimeter = 72 / 25.4f;
    internal static readonly SKSamplingOptions Sampling = new(SKFilterMode.Linear, SKMipmapMode.Linear);

    public static int Pixels(double size) => size > 0 && size < int.MaxValue
        ? Math.Max(1, (int)Math.Round(size, MidpointRounding.AwayFromZero)) : 0;

    public static int PageCapacity(PrintSettings settings)
    {
        var (columns, rows) = Grid(settings);
        return columns * rows;
    }

    private static (int Columns, int Rows) Grid(PrintSettings settings)
    {
        if (settings.Width <= 0 || settings.Height <= 0)
            return (0, 0);
        return ((int)((PageWidth - 2 * Margin + Gap) / (settings.Width + Gap)),
            (int)((GridBottom - GridTop + Gap) / (settings.Height + Gap)));
    }

    public static Placement[][] Layout(PrintSettings settings, IReadOnlyList<Artwork> artwork)
    {
        var (columns, rows) = Grid(settings);
        if (columns * rows <= 0 || artwork.Count == 0 || artwork.Count > MaxCopies ||
            artwork.Any(item => item.Copies is < 1 or > MaxCopies) || artwork.Sum(item => item.Copies) > MaxCopies)
            return [];

        var indices = artwork.SelectMany((item, index) => Enumerable.Repeat(index, item.Copies));
        return indices.Chunk(columns * rows).Select(page =>
        {
            int pageColumns = Math.Min(columns, page.Length);
            double left = (PageWidth - pageColumns * settings.Width - (pageColumns - 1) * Gap) / 2;
            return page.Select((artworkIndex, i) =>
            {
                double x = left + i % pageColumns * (settings.Width + Gap);
                double y = GridTop + i / pageColumns * (settings.Height + Gap);
                return new Placement(artworkIndex, Rect(x, y, settings.Width, settings.Height));
            }).ToArray();
        }).ToArray();
    }

    public static SKRect Crop(SKBitmap bitmap, SKRect area, double zoom = 1, double panX = 0, double panY = 0)
    {
        double scale = Math.Max((double)area.Width / bitmap.Width, (double)area.Height / bitmap.Height) * Math.Clamp(zoom, 1, 3.5);
        double width = bitmap.Width * scale;
        double height = bitmap.Height * scale;
        return Rect(area.Left + (area.Width - width) * (1 - Math.Clamp(panX, -1, 1)) / 2,
            area.Top + (area.Height - height) * (1 - Math.Clamp(panY, -1, 1)) / 2, width, height);
    }

    internal static SKRect Fit(SKBitmap bitmap, SKRect area)
    {
        double scale = Math.Min((double)area.Width / bitmap.Width, (double)area.Height / bitmap.Height);
        return Rect(area.MidX - bitmap.Width * scale / 2, area.MidY - bitmap.Height * scale / 2,
            bitmap.Width * scale, bitmap.Height * scale);
    }

    internal static SKRect Rect(double x, double y, double width, double height) =>
        new((float)x, (float)y, (float)(x + width), (float)(y + height));

    public static SKBitmap Rasterize(PrintSettings settings, Artwork artwork)
    {
        Profile.Require(settings.CanRasterize, "The artwork is too large for this resolution. Lower the dpi.");
        var bitmap = NewBitmap(settings.PixelWidth, settings.PixelHeight);
        using var canvas = new SKCanvas(bitmap);
        canvas.Scale(bitmap.Width / (float)settings.Width, bitmap.Height / (float)settings.Height);
        DrawArtwork(canvas, artwork, Rect(0, 0, settings.Width, settings.Height));
        return bitmap;
    }

    internal static SKBitmap NewBitmap(int width, int height) =>
        new(new SKImageInfo(width, height, SKColorType.Bgra8888, SKAlphaType.Premul));

    public static void DrawArtwork(SKCanvas canvas, Artwork artwork, SKRect area)
    {
        canvas.Save();
        canvas.ClipRect(area);
        using var white = new SKPaint { Color = SKColors.White };
        canvas.DrawRect(area, white);
        DrawImage(canvas, artwork.Bitmap, Crop(artwork.Bitmap, area, artwork.Zoom, artwork.PanX, artwork.PanY));
        canvas.Restore();
    }

    internal static void DrawImage(SKCanvas canvas, SKBitmap bitmap, SKRect target)
    {
        using var image = SKImage.FromBitmap(bitmap);
        canvas.DrawImage(image, target, Sampling);
    }

    public static void DrawPage(SKCanvas canvas, PrintSettings settings, IReadOnlyList<Artwork> artwork,
        Placement[] page, int pageNumber, int totalPages, bool forPrint = false)
    {
        canvas.Clear(SKColors.White);
        using var ink = new SKPaint { Color = new(30, 38, 33), IsAntialias = true, StrokeWidth = 0.35f };
        using var text = new SKFont(SKTypeface.Default, 3.1f);
        using var heading = new SKFont(SKTypeface.Default, 5.3f);
        canvas.DrawText("Cartrest", 10, 14, SKTextAlign.Left, heading, ink);
        canvas.DrawText($"Vinyl label sheet  |  {settings.Dpi} dpi  |  Page {pageNumber} of {totalPages}",
            10, 21, SKTextAlign.Left, text, ink);
        canvas.DrawText("Print at Actual Size (100%)", 200, 21, SKTextAlign.Right, text, ink);

        int previous = -1;
        SKBitmap? raster = null;
        try
        {
            foreach (var placement in page)
            {
                if (forPrint)
                {
                    if (previous != placement.ArtworkIndex)
                    {
                        raster?.Dispose();
                        raster = Rasterize(settings, artwork[placement.ArtworkIndex]);
                        previous = placement.ArtworkIndex;
                    }
                    DrawImage(canvas, raster!, placement.Area);
                }
                else
                {
                    DrawArtwork(canvas, artwork[placement.ArtworkIndex], placement.Area);
                }

                var region = settings.TrimRegion with
                {
                    X = placement.Area.Left + settings.Bleed,
                    Y = placement.Area.Top + settings.Bleed
                };
                using var cut = Outline.Path(Outline.ForRegion(region));
                using var dash = SKPathEffect.CreateDash([1.5f, 0.9f], 0);
                using var cutInk = new SKPaint { Style = SKPaintStyle.Stroke, StrokeWidth = 0.23f, IsAntialias = true, PathEffect = dash };
                cutInk.Color = SKColors.White;
                cutInk.StrokeWidth = 0.53f;
                canvas.DrawPath(cut, cutInk);
                cutInk.Color = ink.Color;
                cutInk.StrokeWidth = 0.23f;
                canvas.DrawPath(cut, cutInk);
            }
        }
        finally
        {
            raster?.Dispose();
        }

        const int rulerX = 10;
        const int rulerY = 275;
        canvas.DrawLine(rulerX, rulerY, rulerX + 50, rulerY, ink);
        for (int i = 0; i <= 50; i += 5)
            canvas.DrawLine(rulerX + i, rulerY - (i % 10 == 0 ? 2.2f : 1.3f), rulerX + i, rulerY + 1.5f, ink);
        canvas.DrawText("50 mm reference ruler", rulerX, 283, SKTextAlign.Left, text, ink);
    }

    public static void WritePdf(Stream destination, PrintSettings settings, IReadOnlyList<Artwork> artwork)
    {
        var pages = Layout(settings, artwork);
        Profile.Require(pages.Length > 0, "Fit the artwork inside A4 and use up to 24 copies.");
        Profile.Require(settings.CanRasterize, "The artwork is too large for this resolution. Lower the dpi.");
        using var document = SKDocument.CreatePdf(destination, new SKDocumentPdfMetadata
        {
            Title = "Cartrest vinyl label sheet",
            Creator = "Cartrest",
            RasterDpi = settings.Dpi
        }) ?? throw new IOException("The PDF could not be created.");
        for (int i = 0; i < pages.Length; i++)
        {
            var canvas = document.BeginPage(PageWidth * PointsPerMillimeter, PageHeight * PointsPerMillimeter);
            canvas.Scale(PointsPerMillimeter);
            DrawPage(canvas, settings, artwork, pages[i], i + 1, pages.Length, forPrint: true);
            document.EndPage();
        }
        document.Close();
    }

    public static void WritePng(Stream destination, SKBitmap bitmap, int dpi)
    {
        using var image = SKImage.FromBitmap(bitmap);
        using var encoded = image.Encode(SKEncodedImageFormat.Png, 100)
            ?? throw new IOException("The PNG could not be created.");
        var png = encoded.AsSpan();

        // Insert physical resolution immediately after the required 13-byte IHDR.
        const int afterHeader = 33;
        Span<byte> chunk = stackalloc byte[21];
        BinaryPrimitives.WriteUInt32BigEndian(chunk, 9);
        "pHYs"u8.CopyTo(chunk[4..]);
        uint dotsPerMeter = (uint)Math.Round(Math.Clamp(dpi, 72, 1200) / 0.0254);
        BinaryPrimitives.WriteUInt32BigEndian(chunk[8..], dotsPerMeter);
        BinaryPrimitives.WriteUInt32BigEndian(chunk[12..], dotsPerMeter);
        chunk[16] = 1;
        BinaryPrimitives.WriteUInt32BigEndian(chunk[17..], Crc32(chunk[4..17]));
        destination.Write(png[..afterHeader]);
        destination.Write(chunk);
        destination.Write(png[afterHeader..]);
    }

    private static uint Crc32(ReadOnlySpan<byte> data)
    {
        uint crc = uint.MaxValue;
        foreach (byte value in data)
        {
            crc ^= value;
            for (int i = 0; i < 8; i++)
                crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320u : 0u);
        }
        return ~crc;
    }

    public static SKBitmap ReadBitmap(string path)
    {
        using var file = File.OpenRead(path);
        Profile.Require(file.Length <= 100_000_000, "Choose an image smaller than 100 MB.");
        using var codec = SKCodec.Create(file) ?? throw new InvalidDataException("Choose a supported image, such as PNG, JPEG or WebP.");
        var info = codec.Info;
        Profile.Require(info.Width > 0 && info.Height > 0 && (long)info.Width * info.Height <= 64_000_000,
            "Choose an image under 64 megapixels.");
        using var source = SKBitmap.Decode(codec) ?? throw new InvalidDataException("The image could not be decoded.");
        int exif = (int)codec.EncodedOrigin;
        int width = exif >= 5 ? source.Height : source.Width;
        int height = exif >= 5 ? source.Width : source.Height;
        double factor = Math.Min(1, Math.Min(6000d / Math.Max(width, height), Math.Sqrt(MaxPixels / ((double)width * height))));
        var result = NewBitmap(Pixels(width * factor), Pixels(height * factor));
        using var canvas = new SKCanvas(result);
        canvas.Clear(SKColors.Transparent);
        canvas.Scale(result.Width / (float)width, result.Height / (float)height);
        // Transform the encoded pixel origin into an upright image before framing.
        switch (codec.EncodedOrigin)
        {
            case SKEncodedOrigin.TopRight: canvas.Translate(width, 0); canvas.Scale(-1, 1); break;
            case SKEncodedOrigin.BottomRight: canvas.Translate(width, height); canvas.Scale(-1, -1); break;
            case SKEncodedOrigin.BottomLeft: canvas.Translate(0, height); canvas.Scale(1, -1); break;
            case SKEncodedOrigin.LeftTop: canvas.RotateDegrees(90); canvas.Scale(1, -1); break;
            case SKEncodedOrigin.RightTop: canvas.Translate(width, 0); canvas.RotateDegrees(90); break;
            case SKEncodedOrigin.RightBottom: canvas.Translate(width, height); canvas.RotateDegrees(90); canvas.Scale(-1, 1); break;
            case SKEncodedOrigin.LeftBottom: canvas.Translate(0, height); canvas.RotateDegrees(-90); break;
        }
        DrawImage(canvas, source, Rect(0, 0, source.Width, source.Height));
        return result;
    }
}
