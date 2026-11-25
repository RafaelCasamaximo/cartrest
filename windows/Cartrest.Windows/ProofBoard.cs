using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Cartrest.Core;
using SkiaSharp;

namespace Cartrest.Windows;

internal sealed class ProofBoard : FrameworkElement
{
    private Brush mat = Ui.Panel;
    private Pen fine = new(Ui.Edge, 1);
    private Pen major = new(Ui.Edge, 1);
    private BitmapSource? image;
    private Brush ornament = Ui.Secondary;
    public bool Paper { get; set; }

    public void Update(Palette palette, BitmapSource? proof)
    {
        image = proof;
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
        fine = new(new SolidColorBrush(Color.FromArgb((byte)(opacity * 0.12), color.Red, color.Green, color.Blue)), 1);
        major = new(new SolidColorBrush(Color.FromArgb((byte)(opacity * 0.23), color.Red, color.Green, color.Blue)), 1);
        ornament = new SolidColorBrush(Color.FromArgb((byte)(opacity * 0.64), color.Red, color.Green, color.Blue));
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
        dc.PushClip(new RectangleGeometry(viewport, 11, 11));
        dc.DrawRectangle(mat, null, viewport);
        const double inset = 19;
        const double grid = 19;
        if (viewport.Width > inset * 2 && viewport.Height > inset * 2)
        {
            var inner = new Rect(inset, inset, viewport.Width - 2 * inset, viewport.Height - 2 * inset);
            dc.DrawRectangle(null, major, inner);
            for (int i = 1; i * grid < inner.Width; i++)
            {
                double x = inset + i * grid;
                dc.DrawLine(i % 5 == 0 ? major : fine, new(x, inset), new(x, inner.Bottom));
                if (i % 5 == 0)
                    dc.DrawLine(major, new(x, 10), new(x, inset));
            }
            for (int i = 1; i * grid < inner.Height; i++)
            {
                double y = inset + i * grid;
                dc.DrawLine(i % 5 == 0 ? major : fine, new(inset, y), new(inner.Right, y));
                if (i % 5 == 0)
                    dc.DrawLine(major, new(10, y), new(inset, y));
            }
            foreach (var p in new[] { inner.TopLeft, inner.TopRight, inner.BottomLeft, inner.BottomRight })
                dc.DrawEllipse(ornament, null, p, 2, 2);
        }

        if (image is not null)
        {
            const double roomForMeter = 60;
            double scale = Math.Min(Math.Max(0, viewport.Width - 125) / image.PixelWidth,
                Math.Max(0, viewport.Height - roomForMeter - 48) / image.PixelHeight);
            scale = Math.Min(scale, Paper ? 0.94 : 0.84);
            double width = image.PixelWidth * scale;
            double height = image.PixelHeight * scale;
            if (scale > 0)
                dc.DrawImage(image, new((viewport.Width - width) / 2, (viewport.Height - height - roomForMeter) / 2, width, height));
        }
        dc.Pop();
    }
}

internal static class ProofRenderer
{
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
        const double pad = 15;
        var (bitmap, canvas) = Picture((body.Width + 2 * pad) * factor, (body.Height + 2 * pad) * factor);
        using (bitmap)
        using (canvas)
        {
            canvas.Translate((float)(pad * factor), (float)(pad * factor));
            canvas.Scale((float)factor);
            using var shape = Outline.Path(Outline.ForBody(body));
            using var blur = SKMaskFilter.CreateBlur(SKBlurStyle.Normal, 5);
            using var shadow = new SKPaint { Color = new(4, 10, 8, 175), IsAntialias = true, MaskFilter = blur };
            canvas.Save();
            canvas.Translate(0, 5);
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
            if (geometry.Grip is { } grip)
            {
                using var path = Outline.Path(Outline.ForRegion(grip));
                canvas.DrawPath(path, paint);
            }
            if (geometry.Arrow is { } arrow)
            {
                using var path = Outline.Path(Outline.ForArrow(arrow));
                canvas.DrawPath(path, paint);
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
        const double pad = 6;
        var (bitmap, canvas) = Picture(settings.Width + pad * 2, settings.Height + pad * 2);
        using (bitmap)
        using (canvas)
        {
            canvas.Translate((float)pad, (float)pad);
            var rect = new SKRect(0, 0, (float)settings.Width, (float)settings.Height);
            if (art is not null)
                PrintLayout.DrawArtwork(canvas, art, rect);
            else
            {
                using var paper = new SKPaint { Color = new(246, 246, 237), IsAntialias = true };
                canvas.DrawRect(rect, paper);
            }
            using var trim = Outline.Path(Outline.ForRegion(settings.TrimRegion));
            using var dash = SKPathEffect.CreateDash([1.7f, 1.0f], 0);
            using var ink = new SKPaint { Color = SKColors.White, IsAntialias = true, Style = SKPaintStyle.Stroke, StrokeWidth = .9f };
            canvas.DrawPath(trim, ink);
            ink.Color = new(21, 36, 30);
            ink.StrokeWidth = .45f;
            ink.PathEffect = dash;
            canvas.DrawPath(trim, ink);
            return BitmapSource(bitmap);
        }
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
        double scale = 860 / Math.Max(width, height);
        var bitmap = new SKBitmap(new SKImageInfo(PrintLayout.Pixels(width * scale), PrintLayout.Pixels(height * scale), SKColorType.Bgra8888, SKAlphaType.Premul));
        var canvas = new SKCanvas(bitmap);
        canvas.Clear(SKColors.Transparent);
        canvas.Scale((float)scale);
        return (bitmap, canvas);
    }
}
