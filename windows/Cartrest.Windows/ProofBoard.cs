using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Cartrest.Core;
using SkiaSharp;

namespace Cartrest.Windows;

internal sealed class ProofBoard : FrameworkElement
{
    private Brush mat = Brushes.Transparent;
    private Pen fine = new(Brushes.Transparent, 1);
    private Pen major = new(Brushes.Transparent, 1);
    private BitmapSource? image;
    private double physicalWidth = 100;
    private bool paper;
    private bool pageControls;

    public void Update(Palette palette, BitmapSource? proof, double width, bool paper, bool pageControls)
    {
        image = proof;
        physicalWidth = width;
        this.paper = paper;
        this.pageControls = pageControls;
        var colors = new[] { palette.Mat.Highlight, palette.Mat.Center, palette.Mat.Shadow };
        var stops = new GradientStopCollection();
        for (int i = 0; i < colors.Length; i++)
        {
            var baseColor = SKColor.Parse(colors[i]);
            if (palette.Mat.Tint is { } tint)
                baseColor = Mix(baseColor, SKColor.Parse(tint.Color), tint.Strength);
            stops.Add(new(Ui.ColorFrom(baseColor), i * 0.5));
        }

        var (start, end) = palette.Mat.Direction switch
        {
            "horizontal" => (new Point(0, 0.5), new Point(1, 0.5)),
            "vertical" => (new Point(0.5, 0), new Point(0.5, 1)),
            "reverseDiagonal" => (new Point(1, 0), new Point(0, 1)),
            _ => (new Point(0, 0), new Point(1, 1))
        };
        mat = new LinearGradientBrush(stops, start, end);
        byte opacity = (byte)Math.Round(255 * palette.Mat.GridOpacity);
        var color = SKColor.Parse(palette.Grid);
        fine = new(new SolidColorBrush(Color.FromArgb((byte)(opacity * 0.10), color.Red, color.Green, color.Blue)), .65);
        major = new(new SolidColorBrush(Color.FromArgb((byte)(opacity * 0.17), color.Red, color.Green, color.Blue)), .75);
        InvalidateVisual();
    }

    private static SKColor Mix(SKColor a, SKColor b, double amount)
    {
        byte Channel(byte x, byte y) => (byte)Math.Round(x + (y - x) * amount);
        return new(Channel(a.Red, b.Red), Channel(a.Green, b.Green), Channel(a.Blue, b.Blue));
    }

    protected override void OnRender(DrawingContext dc)
    {
        var viewport = new Rect(RenderSize);
        if (viewport.Width <= 0 || viewport.Height <= 0)
            return;
        dc.DrawRectangle(mat, null, viewport);
        var bounds = FitProof(viewport);
        double ratio = bounds.IsEmpty
            ? Math.Min(viewport.Width, viewport.Height) * .68 / physicalWidth
            : bounds.Width / physicalWidth;
        if (!double.IsFinite(ratio) || ratio <= 0)
            return;

        var origin = bounds.IsEmpty ? new Point(viewport.Width / 2, viewport.Height / 2) : bounds.TopLeft;
        DrawGrid(origin.X, viewport.Width, x => (new Point(x, 0), new Point(x, viewport.Height)));
        DrawGrid(origin.Y, viewport.Height, y => (new Point(0, y), new Point(viewport.Width, y)));
        if (image is not null && !bounds.IsEmpty)
            dc.DrawImage(image, bounds);

        void DrawGrid(double offset, double length, Func<double, (Point, Point)> endpoints)
        {
            // The mat is measured in millimeters, including when the coaster size changes.
            double step = ratio * 5;
            int every = 4;
            if (step < 4)
            {
                step *= every;
                every = 1;
            }
            if (step < 4)
                return;
            int first = (int)Math.Ceiling(-offset / step);
            int last = (int)Math.Floor((length - offset) / step);
            for (int index = first; index <= last; index++)
            {
                var (start, end) = endpoints(offset + index * step);
                dc.DrawLine(index % every == 0 ? major : fine, start, end);
            }
        }
    }

    private Rect FitProof(Rect viewport)
    {
        if (image is null)
            return Rect.Empty;

        const double top = 17;
        var height = viewport.Height - MeasurementDisplay.PreviewClearance - (pageControls ? 27 : 0) - top;
        var width = viewport.Width - (paper ? 80 : 52);
        if (height <= 0 || width <= 0)
            return Rect.Empty;

        double scale = Math.Min(width / image.PixelWidth, height / image.PixelHeight);
        width = image.PixelWidth * scale;
        var scaledHeight = image.PixelHeight * scale;
        return new Rect((viewport.Width - width) / 2, top + (height - scaledHeight) / 2, width, scaledHeight);
    }

}

internal static class ProofRenderer
{
    internal const double CoasterPadding = 10;
    internal const double CutPadding = 7;
    private static readonly ConditionalWeakTable<SKBitmap, BitmapSource> Thumbnails = new();
    private static readonly SKSamplingOptions Smooth = new(SKFilterMode.Linear, SKMipmapMode.Linear);

    internal static BitmapSource Thumbnail(Artwork art) => Thumbnails.GetValue(art.Bitmap, original =>
    {
        using var thumbnail = new SKBitmap(new SKImageInfo(96, 96, SKColorType.Bgra8888, SKAlphaType.Premul));
        using var canvas = new SKCanvas(thumbnail);
        using var picture = SKImage.FromBitmap(original);
        canvas.Clear(SKColors.Transparent);
        canvas.DrawImage(picture, PrintLayout.Crop(original, SKRect.Create(96, 96)), Smooth);
        return BitmapSource(thumbnail);
    });

    internal static BitmapSource RenderDesign(SKBitmap label, PrintSettings settings)
    {
        using var canvas = new SKCanvas(label);
        canvas.Scale(label.Width / (float)settings.Width, label.Height / (float)settings.Height);
        using var trim = Outline.Path(Outline.ForRegion(settings.TrimRegion));
        canvas.Save();
        canvas.ClipPath(trim, SKClipOperation.Difference, antialias: true);
        using var bleed = new SKPaint { Color = new(35, 71, 58, 110), IsAntialias = true };
        canvas.DrawRect(SKRect.Create((float)settings.Width, (float)settings.Height), bleed);
        canvas.Restore();
        DrawTrim(canvas, trim);
        return BitmapSource(label);
    }

    public static BitmapSource BitmapSource(SKBitmap bitmap)
    {
        var source = System.Windows.Media.Imaging.BitmapSource.Create(bitmap.Width, bitmap.Height, 96, 96,
            PixelFormats.Pbgra32, null, bitmap.GetPixels(), bitmap.ByteCount, bitmap.RowBytes);
        source.Freeze();
        return source;
    }

    public static BitmapSource RenderCoaster(Workspace workspace, Artwork? art)
    {
        var profile = workspace.Profile;
        var geometry = profile.Geometry;
        var palette = profile.Palette;
        var body = geometry.Body;
        double factor = profile.Scale(workspace.Width);
        var (bitmap, canvas) = Picture((body.Width + 2 * CoasterPadding) * factor, (body.Height + 2 * CoasterPadding) * factor);
        using (bitmap)
        using (canvas)
        {
            canvas.Translate((float)(CoasterPadding * factor), (float)(CoasterPadding * factor));
            canvas.Scale((float)factor);
            using var shape = Outline.Path(Outline.ForBody(body));
            using var blur = SKMaskFilter.CreateBlur(SKBlurStyle.Normal, 3.4f);
            using var shadow = new SKPaint { Color = new(4, 10, 8, 175), IsAntialias = true, MaskFilter = blur };
            canvas.Save();
            canvas.Translate(0, 4);
            canvas.DrawPath(shape, shadow);
            canvas.Restore();
            using var shell = SKShader.CreateLinearGradient(new(0, 0), new((float)body.Width, (float)body.Height),
                [SKColor.Parse(palette.Shell.Highlight), SKColor.Parse(palette.Shell.Shadow)], null, SKShaderTileMode.Clamp);
            using var paint = new SKPaint { Shader = shell, IsAntialias = true };
            canvas.DrawPath(shape, paint);
            paint.Shader = null;
            paint.Style = SKPaintStyle.Stroke;
            paint.StrokeWidth = 0.7f;
            paint.Color = new(255, 255, 255, 46);
            canvas.DrawPath(shape, paint);

            using var recess = Outline.Path(Outline.ForRegion(geometry.Recess));
            paint.Style = SKPaintStyle.Fill;
            paint.Color = SKColor.Parse(palette.Recess);
            canvas.DrawPath(recess, paint);
            using var bevel = SKShader.CreateLinearGradient(
                new(0, (float)geometry.Recess.Y),
                new(0, (float)(geometry.Recess.Y + geometry.Recess.Height)),
                [new SKColor(0, 0, 0, 155), new SKColor(255, 255, 255, 81)], null, SKShaderTileMode.Clamp);
            using var rim = new SKPaint
            {
                IsAntialias = true, Style = SKPaintStyle.Stroke, StrokeWidth = .55f, Shader = bevel
            };
            canvas.DrawPath(recess, rim);
            if (geometry.Grip is { } grip)
            {
                using var path = Outline.Path(Outline.ForRegion(grip));
                canvas.DrawPath(path, paint);
            }
            if (geometry.Arrow is { } arrow)
            {
                using var path = Outline.Path(Outline.ForArrow(arrow));
                canvas.DrawPath(path, paint);
                canvas.DrawPath(path, rim);
            }
            if (art is not null)
            {
                var label = geometry.Label;
                double bleed = workspace.Bleed / factor;
                using var vinyl = Outline.Path(Outline.ForRegion(label));
                canvas.Save();
                canvas.ClipPath(vinyl, antialias: true);
                var area = new SKRect((float)(label.X - bleed), (float)(label.Y - bleed),
                    (float)(label.X + label.Width + bleed), (float)(label.Y + label.Height + bleed));
                PrintLayout.DrawArtwork(canvas, art, area);
                canvas.Restore();
            }
            return BitmapSource(bitmap);
        }
    }

    public static BitmapSource RenderCut(PrintSettings settings, Artwork? art)
    {
        var (bitmap, canvas) = Picture(settings.Width + CutPadding * 2, settings.Height + CutPadding * 2);
        using (bitmap)
        using (canvas)
        {
            canvas.Translate((float)CutPadding, (float)CutPadding);
            var rect = new SKRect(0, 0, (float)settings.Width, (float)settings.Height);
            if (art is not null)
                PrintLayout.DrawArtwork(canvas, art, rect);
            else
            {
                using var paper = new SKPaint { Color = new(246, 246, 237), IsAntialias = true };
                canvas.DrawRect(rect, paper);
            }
            using var trim = Outline.Path(Outline.ForRegion(settings.TrimRegion));
            DrawTrim(canvas, trim);
            return BitmapSource(bitmap);
        }
    }

    private static void DrawTrim(SKCanvas canvas, SKPath trim)
    {
        using var dash = SKPathEffect.CreateDash([1.4f, 0.9f], 0);
        using var ink = new SKPaint
        {
            Color = new SKColor(255, 255, 255, 219),
            IsAntialias = true, Style = SKPaintStyle.Stroke, StrokeWidth = .46f
        };
        canvas.DrawPath(trim, ink);
        ink.Color = new(38, 50, 43, 207);
        ink.StrokeWidth = .28f;
        ink.PathEffect = dash;
        canvas.DrawPath(trim, ink);
    }

    public static BitmapSource RenderSheet(PrintSettings settings, IReadOnlyList<Artwork> artwork, Placement[][] pages, int page)
    {
        var (bitmap, canvas) = Picture(PrintLayout.PageWidth, PrintLayout.PageHeight);
        using (bitmap)
        using (canvas)
        {
            int index = Math.Clamp(page, 0, Math.Max(0, pages.Length - 1));
            PrintLayout.DrawPage(canvas, settings, artwork, pages.ElementAtOrDefault(index) ?? [], index + 1, Math.Max(1, pages.Length));
            return BitmapSource(bitmap);
        }
    }

    private static (SKBitmap Bitmap, SKCanvas Canvas) Picture(double width, double height)
    {
        double scale = 1440 / Math.Max(width, height);
        var bitmap = new SKBitmap(new SKImageInfo(PrintLayout.Pixels(width * scale), PrintLayout.Pixels(height * scale), SKColorType.Bgra8888, SKAlphaType.Premul));
        var canvas = new SKCanvas(bitmap);
        canvas.Clear(SKColors.Transparent);
        canvas.Scale((float)scale);
        return (bitmap, canvas);
    }
}
