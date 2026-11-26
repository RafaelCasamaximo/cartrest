using System.Numerics;

namespace Cartrest.Core;

/// <summary>A base-down rack sized to the portion of a coaster covered by its guides.</summary>
public sealed class CoasterHolder
{
    public const int MinimumSlots = 1;
    public const int MaximumSlots = 24;
    public const int DefaultSlots = 4;
    public const double MinimumClearance = 0.2;
    public const double MaximumClearance = 1.5;
    public const double DefaultClearance = 0.5;

    private const double Wall = 3.2;
    private const double Divider = 4.0;
    private const double Base = 3.2;

    private readonly double guideHeight;
    private readonly double finReach;
    private readonly double footDepth;

    public int SlotCount { get; }
    public double SlotWidth { get; }
    public double SlotDepth { get; }
    public double Width => SlotWidth + 2 * Wall;
    public double Depth => 2 * footDepth + SlotCount * (SlotDepth + Divider) + Divider;
    public double Height => Base + guideHeight;

    public CoasterHolder(Profile profile, double coasterWidth, int slotCount, double clearance)
    {
        Profile.Require(slotCount is >= MinimumSlots and <= MaximumSlots,
            $"Choose between {MinimumSlots} and {MaximumSlots} holder slots.");
        Profile.Require(clearance is >= MinimumClearance and <= MaximumClearance,
            $"Choose a clearance from {MinimumClearance:g} to {MaximumClearance:g} mm per side.");

        var body = profile.Geometry.Body;
        double scale = profile.Scale(coasterWidth);
        double coasterHeight = body.Height * scale;
        guideHeight = Math.Min(44, coasterHeight * 0.34);
        double contactWidth = CartridgeMesh.LowerBodyWidth(body, body.Height - guideHeight / scale) * scale;
        Profile.Require(contactWidth > 0, "The bottom of the coaster must have a measurable width.");

        SlotCount = slotCount;
        SlotWidth = contactWidth + 2 * clearance;
        SlotDepth = body.Thickness * scale + 2 * clearance;
        finReach = Math.Min(8, contactWidth * 0.08);
        footDepth = Math.Max(10, coasterHeight * 0.14);
    }

    public void WriteStl(Stream destination)
    {
        // The end feet extend the base. A divider bounds each opening at both ends.
        double[] xs = [0, Wall, Wall + finReach, Wall + SlotWidth - finReach, Wall + SlotWidth, Width];
        var ys = new List<double>(2 * SlotCount + 4) { 0, footDepth };
        for (int slot = 0; slot < SlotCount; slot++)
        {
            double opening = ys[^1] + Divider;
            ys.Add(opening);
            ys.Add(opening + SlotDepth);
        }
        ys.Add(Depth - footDepth);
        ys.Add(Depth);

        // The last layer of cells bevels the entry by widening each opening.
        double lead = Math.Min(0.8, guideHeight / 4);
        double leadHeight = Math.Min(1.6, guideHeight / 2);
        double[] zs = [0, Base, Height - leadHeight, Height];
        var topXs = (double[])xs.Clone();
        topXs[1] -= lead;
        topXs[4] += lead;
        var topYs = ys.ToArray();
        for (int y = 2; y < ys.Count - 2; y++)
            topYs[y] += y % 2 == 0 ? -lead : lead;

        int columns = xs.Length - 1;
        int rows = ys.Count - 1;
        int layers = zs.Length - 1;
        var triangles = new List<Triangle>();

        // Emit exposed faces on a shared grid so the base, rails and fins form one mesh.
        for (int z = 0; z < layers; z++)
        {
            for (int y = 0; y < rows; y++)
            {
                for (int x = 0; x < columns; x++)
                {
                    if (!IsSolid(x, y, z))
                        continue;
                    var a = Vertex(x, y, z);
                    var b = Vertex(x + 1, y, z);
                    var c = Vertex(x + 1, y + 1, z);
                    var d = Vertex(x, y + 1, z);
                    var e = Vertex(x, y, z + 1);
                    var f = Vertex(x + 1, y, z + 1);
                    var g = Vertex(x + 1, y + 1, z + 1);
                    var h = Vertex(x, y + 1, z + 1);
                    if (!IsSolid(x, y, z - 1)) Face(d, c, b, a);
                    if (!IsSolid(x, y, z + 1)) Face(e, f, g, h);
                    if (!IsSolid(x - 1, y, z)) Face(a, e, h, d);
                    if (!IsSolid(x + 1, y, z)) Face(b, c, g, f);
                    if (!IsSolid(x, y - 1, z)) Face(a, b, f, e);
                    if (!IsSolid(x, y + 1, z)) Face(d, h, g, c);
                }
            }
        }
        CartridgeMesh.WriteStl(destination, triangles, "Cartrest | millimeters | holder base down");

        Vector3 Vertex(int x, int y, int z) => z == layers
            ? new((float)topXs[x], (float)topYs[y], (float)zs[z])
            : new((float)xs[x], (float)ys[y], (float)zs[z]);

        bool IsSolid(int x, int y, int z)
        {
            if (x < 0 || x >= columns || y < 0 || y >= rows || z < 0 || z >= layers)
                return false;
            if (z == 0)
                return true;
            return y > 0 && y < rows - 1 && (x == 0 || x == columns - 1 || (y % 2 == 1 && x != 2));
        }

        void Face(Vector3 a, Vector3 b, Vector3 c, Vector3 d)
        {
            triangles.Add(new(a, b, c));
            triangles.Add(new(a, c, d));
        }
    }
}
