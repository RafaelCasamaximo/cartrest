using SkiaSharp;

namespace Cartrest.Core;

/// <summary>The 2D proof and 3D recipe use the same top-left millimeter outlines.</summary>
public static class Outline
{
    internal static double Snap(double value) => Math.Round(value, 7);
    internal static Point2 Snap(Point2 point) => new(Snap(point.X), Snap(point.Y));

    public static Point2[] ForBody(Body body) => body.Vertices?.Select(Snap).ToArray()
        ?? Footprint(0, 0, body.Width, body.Height, body.CornerRadii);

    public static Point2[] ForRegion(Region region) => Footprint(region.X, region.Y, region.Width, region.Height,
        Radii.Uniform(region.Radius), region.Chamfer);

    public static Point2[] ForArrow(Arrow arrow) =>
    [
        Snap(new Point2(arrow.CenterX - arrow.Width / 2, arrow.Top)),
        Snap(new Point2(arrow.CenterX + arrow.Width / 2, arrow.Top)),
        Snap(new Point2(arrow.CenterX, arrow.Top + arrow.Height))
    ];

    internal static Point2[] Footprint(double x, double y, double width, double height, Radii radii, double chamfer = 0)
    {
        var corners = new[] { new Point2(x + width, y), new(x + width, y + height), new(x, y + height), new(x, y) };
        var radius = new[] { radii.TopRight, radii.BottomRight, radii.BottomLeft, radii.TopLeft };
        var points = new List<Point2>(52);
        for (int index = 0; index < corners.Length; index++)
        {
            var corner = corners[index];
            double r = radius[index];
            if (index == 2 && chamfer > 0)
            {
                points.Add(new(x + chamfer, y + height));
                points.Add(new(x, y + height - chamfer));
                continue;
            }
            if (r == 0)
            {
                points.Add(corner);
                continue;
            }
            double centerX = corner.X + (index < 2 ? -r : r);
            double centerY = corner.Y + (index is 0 or 3 ? r : -r);
            for (int step = 0; step <= 12; step++)
            {
                double angle = (-90 + 90 * index + step * 7.5) * Math.PI / 180;
                points.Add(new(centerX + r * Math.Cos(angle), centerY + r * Math.Sin(angle)));
            }
        }

        var result = new List<Point2>(points.Count);
        foreach (var point in points.Select(Snap))
            if (result.Count == 0 || result[^1] != point)
                result.Add(point);
        if (result.Count > 1 && result[0] == result[^1])
            result.RemoveAt(result.Count - 1);
        return result.ToArray();
    }

    public static SKPath Path(IReadOnlyList<Point2> points, double scale = 1, double x = 0, double y = 0)
    {
        var path = new SKPath();
        path.MoveTo((float)(x + points[0].X * scale), (float)(y + points[0].Y * scale));
        for (int i = 1; i < points.Count; i++)
            path.LineTo((float)(x + points[i].X * scale), (float)(y + points[i].Y * scale));
        path.Close();
        return path;
    }
}
