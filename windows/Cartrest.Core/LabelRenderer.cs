using SkiaSharp;

namespace Cartrest.Core;

public static class LabelRenderer
{
    public static SKBitmap Render(LabelDraft draft, LabelCatalog catalog, PrintSettings settings, int? previewLimit = null)
    {
        double scale = settings.Dpi / 25.4;
        if (previewLimit is int limit)
            scale = Math.Min(scale, limit / Math.Max(settings.Width, settings.Height));
        int width = PrintLayout.Pixels(settings.Width * scale);
        int height = PrintLayout.Pixels(settings.Height * scale);
        Profile.Require(width > 0 && height > 0 && (long)width * height <= PrintLayout.MaxPixels,
            "The label is too large for this resolution. Lower the dpi.");

        var bitmap = PrintLayout.NewBitmap(width, height);
        try
        {
            Draw(draft, catalog, settings, bitmap, scale);
            return bitmap;
        }
        catch
        {
            bitmap.Dispose();
            throw;
        }
    }

    private static void Draw(LabelDraft draft, LabelCatalog catalog, PrintSettings settings, SKBitmap bitmap, double scale)
    {
        using var canvas = new SKCanvas(bitmap);
        canvas.Scale(bitmap.Width / (float)settings.Width, bitmap.Height / (float)settings.Height);
        var area = PrintLayout.Rect(0, 0, settings.Width, settings.Height);
        var trim = settings.Trim;
        canvas.Clear(draft.BackgroundColor);
        float header = draft.HeaderStyle == HeaderStyle.Hidden ? 0 : trim.Height * (float)(draft.Template.HeaderHeight * draft.HeaderHeight);
        double footer = string.IsNullOrWhiteSpace(draft.Code) ? 0 : trim.Height * draft.Template.FooterHeight;

        if (draft.Background is { } art)
        {
            var field = PrintLayout.Rect(trim.Left, trim.Top + header, trim.Width, Math.Max(1, trim.Height - header - footer));
            var frame = draft.Fill ? PrintLayout.Crop(art, area, draft.Zoom, draft.PanX, draft.PanY) : FitBackground(art, field, draft);
            PrintLayout.DrawImage(canvas, art, frame);
        }

        // Apply the print texture before bands and marks so the typography remains sharp.
        if (draft.Noise > 0 || (draft.Halftone != HalftoneMode.Off && draft.HalftoneAmount > 0))
        {
            canvas.Flush();
            PrintTexture.Apply(bitmap, draft, scale);
            bitmap.NotifyPixelsChanged();
        }

        if (header > 0)
            DrawHeader(canvas, draft, catalog, area, trim, header);
        if (footer > 0)
            DrawFooter(canvas, draft, catalog, area, trim, (float)footer);
        if (!string.IsNullOrWhiteSpace(draft.Title))
            Text(canvas, draft.Title.Trim(), catalog.TitleTypeface, draft.TitleColor, trim.MidX,
                trim.Top + trim.Height * (float)draft.TitlePosition, (float)(Math.Min(trim.Width, trim.Height) * 0.115 * draft.TitleScale),
                trim.Width * 0.85f, SKTextAlign.Center);

        foreach (var role in Enum.GetValues<MarkRole>())
            DrawMark(canvas, draft.Marks[(int)role], role, catalog, trim);
    }

    private static SKRect FitBackground(SKBitmap art, SKRect field, LabelDraft draft)
    {
        var fitted = PrintLayout.Fit(art, field);
        double w = fitted.Width * draft.Zoom;
        double h = fitted.Height * draft.Zoom;
        return PrintLayout.Rect(field.MidX - w / 2 + field.Width * draft.PanX * 0.4,
            field.MidY - h / 2 + field.Height * draft.PanY * 0.4, w, h);
    }

    private static void DrawHeader(SKCanvas canvas, LabelDraft draft, LabelCatalog catalog, SKRect area, SKRect trim, float height)
    {
        var layout = catalog.Layout(draft.Template);
        using var band = HeaderBand(layout?.Seam, area, trim, height);
        using var paint = new SKPaint { Color = draft.HeaderColor, IsAntialias = true };
        if (draft.HeaderStyle == HeaderStyle.Shadow)
        {
            using var blur = SKMaskFilter.CreateBlur(SKBlurStyle.Normal, height * 0.05f);
            using var shadow = new SKPaint { IsAntialias = true, Color = new(0, 0, 0, 166), MaskFilter = blur };
            canvas.Save();
            canvas.Translate(0, height * 0.045f);
            canvas.DrawPath(band, shadow);
            canvas.Restore();
        }
        canvas.DrawPath(band, paint);

        string? id = draft.Template.Header;
        var color = draft.HeaderColor;
        if (draft.Template.HeaderOnDark is { } reverse && 0.2126 * color.Red + 0.7152 * color.Green + 0.0722 * color.Blue < 127.5)
            id = reverse;
        var bitmap = draft.HeaderLogo ?? catalog.Asset(id);
        if (bitmap is null)
            return;

        double x = trim.Left + trim.Width * (layout?.LogoCenter.X ?? 0.5);
        double y = trim.Top + height * (layout?.LogoCenter.Y ?? 0.5);
        double w = Math.Min(trim.Width * (layout?.LogoWidth ?? 0.80) * draft.HeaderScale, 2 * Math.Min(x - trim.Left, trim.Right - x));
        double h = height * (layout?.LogoHeight ?? 0.74) * draft.HeaderScale;
        canvas.Save();
        canvas.ClipRect(trim);
        canvas.ClipPath(band, antialias: true);
        PrintLayout.DrawImage(canvas, bitmap, PrintLayout.Fit(bitmap, PrintLayout.Rect(x - w / 2, y - h / 2, w, h)));
        canvas.Restore();
    }

    private static SKPath HeaderBand(HeaderSegment[]? seam, SKRect area, SKRect trim, float height)
    {
        var path = new SKPath();
        float right = area.Right + height;
        float left = area.Left - height;
        float top = area.Top - height;
        path.MoveTo(left, top);
        if (seam is not { Length: > 0 })
        {
            path.LineTo(left, trim.Top + height);
            path.LineTo(right, trim.Top + height);
        }
        else
        {
            SKPoint Locate(Point2 point) => new(trim.Left + trim.Width * (float)point.X, trim.Top + height * (float)point.Y);
            var first = Locate(seam[0].End);
            path.LineTo(left, first.Y);
            path.LineTo(first);
            foreach (var segment in seam.Skip(1))
            {
                var end = Locate(segment.End);
                if (segment.Controls is [var a, var b])
                    path.CubicTo(Locate(a), Locate(b), end);
                else
                    path.LineTo(end);
            }
            path.LineTo(right, Locate(seam[^1].End).Y);
        }
        path.LineTo(right, top);
        path.Close();
        return path;
    }

    private static void DrawFooter(SKCanvas canvas, LabelDraft draft, LabelCatalog catalog, SKRect area, SKRect trim, float height)
    {
        float top = trim.Bottom - height;
        using var band = new SKPaint { Color = draft.FooterColor };
        canvas.DrawRect(new SKRect(area.Left, top, area.Right, area.Bottom), band);
        bool ocr = draft.Template.CodeTypeface == "ocr-b";
        var (x, alignment) = draft.CodeAlignment switch
        {
            CodeAlignment.Left => (trim.Left + trim.Width * 0.045f, SKTextAlign.Left),
            CodeAlignment.Right => (trim.Right - trim.Width * (ocr ? 0.0375f : 0.09f), SKTextAlign.Right),
            _ => (trim.MidX, SKTextAlign.Center)
        };
        Text(canvas, draft.Code.Trim(), ocr ? catalog.OcrTypeface : catalog.CodeTypeface, draft.CodeColor,
            x, top + height * (ocr ? 0.38f : 0.45f), height * 0.54f * (float)draft.CodeScale,
            trim.Width * (ocr ? 0.925f : 0.82f), alignment);
    }

    private static void Text(SKCanvas canvas, string text, SKTypeface typeface, SKColor color,
        float x, float centerY, float size, float maxWidth, SKTextAlign align)
    {
        using var font = new SKFont(typeface, size) { Edging = SKFontEdging.Antialias };
        using var paint = new SKPaint { Color = color, IsAntialias = true };
        float measured = font.MeasureText(text);
        if (measured > maxWidth)
            font.Size *= maxWidth / measured;
        font.MeasureText(text, out var bounds);
        canvas.DrawText(text, x, centerY - bounds.MidY, align, font, paint);
    }

    private static void DrawMark(SKCanvas canvas, LabelMark mark, MarkRole role, LabelCatalog catalog, SKRect trim)
    {
        var bitmap = mark.Custom ?? catalog.Asset(mark.AssetId);
        if (bitmap is null)
            return;
        double width = Math.Min(trim.Width, trim.Width * (role == MarkRole.Rating ? 0.21 : 0.27) * mark.Scale);
        double height = Math.Min(trim.Height, trim.Height * (role == MarkRole.Rating ? 0.21 : 0.14) * mark.Scale);
        double x = Math.Clamp(trim.Left + trim.Width * mark.X, trim.Left + width / 2, trim.Right - width / 2);
        double y = Math.Clamp(trim.Top + trim.Height * mark.Y, trim.Top + height / 2, trim.Bottom - height / 2);
        var frame = PrintLayout.Fit(bitmap, PrintLayout.Rect(x - width / 2, y - height / 2, width, height));
        if (mark.Backing != MarkBacking.None)
        {
            float pad = Math.Min(trim.Width, trim.Height) * 0.015f;
            var backing = frame;
            backing.Inflate(pad, pad);
            using var paint = new SKPaint
            {
                IsAntialias = true,
                Color = mark.Backing == MarkBacking.Light ? new(249, 247, 240, 242) : new(28, 32, 31, 242)
            };
            canvas.DrawRoundRect(backing, pad, pad, paint);
        }
        PrintLayout.DrawImage(canvas, bitmap, frame);
    }
}
