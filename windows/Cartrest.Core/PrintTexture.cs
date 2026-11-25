using SkiaSharp;

namespace Cartrest.Core;

/// <summary>Noise and ink screens use millimeters so the proof and export share their pattern scale.</summary>
internal static class PrintTexture
{
    internal static unsafe void Apply(SKBitmap bitmap, LabelDraft draft, double pixelsPerMillimeter)
    {
        byte* pixels = (byte*)bitmap.GetPixels();
        double step = 1 / pixelsPerMillimeter;
        double noise = draft.Noise * 0.37;
        double grain = Math.Max(draft.Grain, step);
        double amount = draft.HalftoneAmount;
        double period = Math.Max(draft.DotSpacing, step * 1.65);
        double edge = Math.Min(0.36, step / period * 0.75);
        var black = new Screen(draft.Angle, period, edge);
        var cyan = new Screen(draft.Angle - 30, period, edge);
        var magenta = new Screen(draft.Angle + 30, period, edge);
        var yellow = new Screen(draft.Angle - 45, period, edge);

        for (int y = 0; y < bitmap.Height; y++)
        {
            byte* row = pixels + y * bitmap.RowBytes;
            double sy = (y + 0.5) * step;
            uint gy = (uint)(sy / grain);
            for (int x = 0; x < bitmap.Width; x++)
            {
                byte* pixel = row + x * 4;
                double sx = (x + 0.5) * step;
                double blue = pixel[0] / 255d;
                double green = pixel[1] / 255d;
                double red = pixel[2] / 255d;

                if (draft.Halftone == HalftoneMode.Cmyk && amount > 0)
                {
                    double baseInk = Math.Max(red, Math.Max(green, blue));
                    double paper = 1 - black.Ink(sx, sy, 1 - baseInk);
                    double c = baseInk > 0 ? 1 - red / baseInk : 0;
                    double m = baseInk > 0 ? 1 - green / baseInk : 0;
                    double inkY = baseInk > 0 ? 1 - blue / baseInk : 0;
                    red += (paper * (1 - cyan.Ink(sx, sy, c)) - red) * amount;
                    green += (paper * (1 - magenta.Ink(sx, sy, m)) - green) * amount;
                    blue += (paper * (1 - yellow.Ink(sx, sy, inkY)) - blue) * amount;
                }
                else if (draft.Halftone == HalftoneMode.Monochrome && amount > 0)
                {
                    double luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722;
                    double ink = 1 - black.Ink(sx, sy, 1 - luminance);
                    red += (ink - red) * amount;
                    green += (ink - green) * amount;
                    blue += (ink - blue) * amount;
                }

                double grainSample = noise > 0 ? (Hash((uint)(sx / grain), gy) / (double)uint.MaxValue - 0.5) * noise : 0;
                pixel[0] = Channel(blue + grainSample);
                pixel[1] = Channel(green + grainSample);
                pixel[2] = Channel(red + grainSample);
            }
        }
    }

    private static byte Channel(double value) => (byte)Math.Round(Math.Clamp(value, 0, 1) * 255);

    private static uint Hash(uint x, uint y)
    {
        unchecked
        {
            uint n = x * 0x9e3779b9 + y * 0x85ebca6b + 0x7f4a7c15;
            n = (n ^ (n >> 16)) * 0x7feb352d;
            n = (n ^ (n >> 15)) * 0x846ca68b;
            return n ^ (n >> 16);
        }
    }

    private readonly struct Screen(double angle, double period, double edge)
    {
        private readonly double sin = Math.Sin(angle * Math.PI / 180) / period;
        private readonly double cos = Math.Cos(angle * Math.PI / 180) / period;

        internal double Ink(double x, double y, double tone)
        {
            double u = x * cos + y * sin;
            double v = y * cos - x * sin;
            u -= Math.Floor(u) + 0.5;
            v -= Math.Floor(v) + 0.5;
            if (tone <= 0)
                return 0;
            if (tone >= 1)
                return 1;
            return Math.Clamp((Math.Sqrt(tone / Math.PI) - Math.Sqrt(u * u + v * v)) / edge + 0.5, 0, 1);
        }
    }
}
