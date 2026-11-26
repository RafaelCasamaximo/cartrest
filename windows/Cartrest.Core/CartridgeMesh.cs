using System.Numerics;
using System.Text;

namespace Cartrest.Core;

public readonly record struct Triangle(Vector3 A, Vector3 B, Vector3 C)
{
    public Vector3 Cross => Vector3.Cross(B - A, C - A);
    public Triangle Scale(float factor) => new(A * factor, B * factor, C * factor);
}

public sealed class CartridgeMesh
{
    private readonly Profile profile;
    public IReadOnlyList<Triangle> Triangles { get; }

    private CartridgeMesh(Profile profile, List<Triangle> triangles)
    {
        this.profile = profile;
        Triangles = triangles.AsReadOnly();
    }

    public static CartridgeMesh Build(Profile profile)
    {
        var body = profile.Geometry.Body;
        var outer = Outline.ForBody(body);
        ValidateBody(outer, body);
        var (frontCuts, rearCuts) = Recipe(profile);
        var label = Outline.ForRegion(profile.Geometry.Label);
        var recess = Outline.ForRegion(profile.Geometry.Recess);
        foreach (double y in label.Concat(recess).Select(p => p.Y).Distinct())
        {
            if (At(label, y) is { } trim)
                Profile.Require(At(recess, y) is { } lip && trim.Left >= lip.Left && trim.Right <= lip.Right,
                    "The label outline must fit inside its recess, including the corners.");
        }

        // Both faces use the same row seams so a rear channel can open through the rim.
        var outlines = frontCuts.Concat(rearCuts).Select(c => c.Points).Prepend(outer).ToArray();
        var rows = outlines.SelectMany(o => o.Select(p => p.Y)).Distinct().Order().ToArray();
        Profile.Require(rows.Length <= 4096, "Reduce the number of distinct cut heights.");
        var marks = new Dictionary<double, double[]>();
        foreach (var y in rows)
        {
            marks[y] = outlines.Select(o => At(o, y)).OfType<Span>()
                .SelectMany(s => new[] { s.Left, s.Right }).Distinct().Order().ToArray();
        }

        var triangles = new List<Triangle>();
        var front = TriangulateFace(outer, frontCuts, body.Thickness, rows, marks, body.Height, false, triangles);
        var rear = TriangulateFace(outer, rearCuts, 0, rows, marks, body.Height, true, triangles);
        TriangulateWalls(JoinFaces(front, rear), triangles);
        ValidateSolid(triangles);
        return new(profile, triangles);
    }

    public void WriteStl(Stream destination, double width)
    {
        float factor = (float)profile.Scale(width);
        var scaled = Triangles.Select(triangle => triangle.Scale(factor)).ToArray();
        WriteStl(destination, scaled, "Cartrest | millimeters | label face up");
    }

    internal static void WriteStl(Stream destination, IReadOnlyList<Triangle> triangles, string header)
    {
        // STL stores float32 coordinates. Validate the geometry at that precision.
        ValidateSolid(triangles);
        using var writer = new BinaryWriter(destination, Encoding.ASCII, leaveOpen: true);
        writer.Write(Encoding.ASCII.GetBytes(header.PadRight(80)));
        writer.Write((uint)triangles.Count);
        foreach (var triangle in triangles)
        {
            Write(Vector3.Normalize(triangle.Cross));
            Write(triangle.A);
            Write(triangle.B);
            Write(triangle.C);
            writer.Write((ushort)0);
        }

        void Write(Vector3 point)
        {
            writer.Write(point.X);
            writer.Write(point.Y);
            writer.Write(point.Z);
        }
    }

    internal static double LowerBodyWidth(Body body, double cutoff)
    {
        var outline = Outline.ForBody(body);
        // Include the cut through any edge crossing the top of the guide.
        var xs = outline.Where(point => point.Y >= cutoff).Select(point => point.X).ToList();
        if (At(outline, cutoff) is { } span)
        {
            xs.Add(span.Left);
            xs.Add(span.Right);
        }
        return xs.Count > 0 ? xs.Max() - xs.Min() : 0;
    }

    private static void ValidateBody(Point2[] outer, Body body)
    {
        Profile.Require(outer.Length >= 3 && outer.Distinct().Count() == outer.Length &&
            outer.Min(p => p.X) == 0 && outer.Max(p => p.X) == Outline.Snap(body.Width) &&
            outer.Min(p => p.Y) == 0 && outer.Max(p => p.Y) == Outline.Snap(body.Height),
            "Use distinct outline vertices that reach the four declared body bounds.");

        // A one-span scanline cannot represent a split body. Test each open band.
        var rows = outer.Select(p => p.Y).Distinct().Order().ToArray();
        for (int i = 1; i < rows.Length; i++)
        {
            double middle = (rows[i - 1] + rows[i]) / 2;
            int hits = 0;
            for (int j = 0; j < outer.Length; j++)
            {
                var a = outer[j];
                var b = outer[(j + 1) % outer.Length];
                if ((a.Y < middle) != (b.Y < middle))
                    hits++;
            }
            Profile.Require(hits == 2, "The body outline needs one continuous horizontal span.");
        }
        for (int i = 0; i < outer.Length; i++)
        for (int j = i + 2; j < outer.Length; j++)
        {
            if (i == 0 && j == outer.Length - 1)
                continue;
            var a = outer[i];
            var b = outer[(i + 1) % outer.Length];
            var c = outer[j];
            var d = outer[(j + 1) % outer.Length];
            static double Turn(Point2 a, Point2 b, Point2 c) => (b.X - a.X) * (c.Y - a.Y) - (b.Y - a.Y) * (c.X - a.X);
            static bool Spans(double a, double b, double c, double d) => Math.Max(Math.Min(a, b), Math.Min(c, d)) <= Math.Min(Math.Max(a, b), Math.Max(c, d));
            bool crosses = Spans(a.X, b.X, c.X, d.X) && Spans(a.Y, b.Y, c.Y, d.Y) &&
                Turn(a, b, c) * Turn(a, b, d) <= 0 && Turn(c, d, a) * Turn(c, d, b) <= 0;
            Profile.Require(!crosses, "The body outline must have no crossing or touching edges.");
        }
    }

    private sealed record Cut(Point2[] Points, double Z);
    private readonly record struct Span(double Left, double Right);
    private readonly record struct Side(Point2 A, Point2 B, double Z);
    private readonly record struct Wall(Point2 A, Point2 B, double Bottom, double Top);

    private static (List<Cut> Front, List<Cut> Rear) Recipe(Profile profile)
    {
        var g = profile.Geometry;
        var b = g.Body;
        var front = new List<Cut>();
        var rear = new List<Cut>();
        var features = new HashSet<string>(StringComparer.Ordinal);
        foreach (var instruction in profile.Instructions.Skip(1))
        {
            Profile.Require(instruction is not null, "Each model instruction must be an object.");
            var i = instruction!;
            switch (i.Op)
            {
                case "recessLabel":
                    AddFront(i.Op, Outline.ForRegion(g.Recess), g.Recess.Depth);
                    break;
                case "engraveArrow" when g.Arrow is { } arrow:
                    AddFront(i.Op, Outline.ForArrow(arrow), arrow.Depth);
                    break;
                case "recessGrip" when g.Grip is { } grip:
                    AddFront(i.Op, Outline.ForRegion(grip), grip.Depth);
                    break;
                case "rearChannels":
                    Profile.Require(i.Count is >= 1 and <= 64 && i.Count + rear.Count <= 64 &&
                        i.Width > 0 && i.Pitch > i.Width, "Use separated rear channels and at most 64 rear cuts.");
                    for (int index = 0; index < i.Count; index++)
                        AddRear(new(i.X + index * i.Pitch, i.Y, i.Width, b.Height - i.Y, 0, 0, i.Depth));
                    break;
                case "rearSlot":
                    var slot = new Region(i.X, i.Y, i.Width, b.Height - i.Y, 0, 0, i.Depth);
                    Profile.ValidateRegion(slot, b, "rear slot", cut: true);
                    Profile.Require(i.Radius >= 0 && i.Radius <= Math.Min(i.Width / 2, slot.Height),
                        "The rear slot radius must fit at its upper end.");
                    rear.Add(new(Outline.Footprint(slot.X, slot.Y, slot.Width, slot.Height, new(i.Radius, i.Radius, 0, 0)), slot.Depth));
                    break;
                case "rearRecess":
                    AddRear(new(i.X, i.Y, i.Width, i.Height, i.Radius, i.Chamfer, i.Depth));
                    break;
                default:
                    throw new InvalidDataException($"Unsupported or incomplete model instruction '{i.Op}'.");
            }
        }

        Profile.Require(features.Contains("recessLabel") && features.Contains("engraveArrow") == (g.Arrow is not null) &&
            features.Contains("recessGrip") == (g.Grip is not null), "Provide one operation for each front feature.");
        Profile.Require(rear.Count <= 64, "Use at most 64 individual rear cuts.");
        Profile.Require(front.Min(c => c.Z) > rear.Select(c => c.Z).DefaultIfEmpty(0).Max(),
            "Leave material between the deepest front and rear cuts.");
        return (front, rear);

        void AddFront(string name, Point2[] points, double depth)
        {
            Profile.Require(features.Add(name), $"Use one '{name}' operation.");
            front.Add(new(points, b.Thickness - depth));
        }

        void AddRear(Region region)
        {
            Profile.ValidateRegion(region, b, "rear cut", cut: true);
            rear.Add(new(Outline.ForRegion(region), region.Depth));
        }
    }

    private static Span? At(IReadOnlyList<Point2> outline, double y)
    {
        double left = double.PositiveInfinity;
        double right = double.NegativeInfinity;
        for (int i = 0; i < outline.Count; i++)
        {
            var a = outline[i];
            var b = outline[(i + 1) % outline.Count];
            if (y < Math.Min(a.Y, b.Y) || y > Math.Max(a.Y, b.Y))
                continue;
            if (a.Y == b.Y)
            {
                left = Math.Min(left, Math.Min(a.X, b.X));
                right = Math.Max(right, Math.Max(a.X, b.X));
                continue;
            }
            double x = Outline.Snap(a.X + (y - a.Y) * (b.X - a.X) / (b.Y - a.Y));
            left = Math.Min(left, x);
            right = Math.Max(right, x);
        }
        return left <= right ? new(left, right) : null;
    }

    private readonly record struct Edge(Point2 First, Point2 Second)
    {
        public static Edge Between(Point2 a, Point2 b) =>
            a.X < b.X || a.X == b.X && a.Y < b.Y ? new(a, b) : new(b, a);
    }

    private static Dictionary<Edge, List<Side>> TriangulateFace(Point2[] outer, List<Cut> cuts, double flatZ,
        double[] rows, Dictionary<double, double[]> marks, double height, bool rear, List<Triangle> triangles)
    {
        var edges = new Dictionary<Edge, List<Side>>();
        for (int i = 1; i < rows.Length; i++)
        {
            double top = rows[i - 1];
            double bottom = rows[i];
            if (At(outer, top) is not { } upper || At(outer, bottom) is not { } lower)
                throw new InvalidDataException("A cut extends beyond the cartridge outline.");

            double middle = (top + bottom) / 2;
            var active = cuts.Select(cut => (cut, span: At(cut.Points, middle))).Where(x => x.span.HasValue)
                .OrderBy(x => x.span!.Value.Left);
            double leftTop = upper.Left;
            double leftBottom = lower.Left;
            foreach (var (cut, _) in active)
            {
                var t = At(cut.Points, top)!.Value;
                var b = At(cut.Points, bottom)!.Value;
                Profile.Require(leftTop <= t.Left && t.Right <= upper.Right && leftBottom <= b.Left && b.Right <= lower.Right,
                    "Cuts on one face must stay inside the body and avoid overlap.");
                AddCell(new(leftTop, t.Left), new(leftBottom, b.Left), flatZ);
                AddCell(t, b, cut.Z);
                leftTop = t.Right;
                leftBottom = b.Right;
            }
            AddCell(new(leftTop, upper.Right), new(leftBottom, lower.Right), flatZ);

            void AddCell(Span t, Span b, double z)
            {
                if (t.Left == t.Right && b.Left == b.Right)
                    return;
                // Keep collinear splits along each horizontal edge and fan from the interior.
                var polygon = marks[bottom].Where(x => x >= b.Left && x <= b.Right)
                    .Select(x => new Point2(x, Outline.Snap(height - bottom)))
                    .Concat(marks[top].Reverse().Where(x => x >= t.Left && x <= t.Right)
                        .Select(x => new Point2(x, Outline.Snap(height - top)))).ToArray();
                var center = Vertex(new(polygon.Average(p => p.X), polygon.Average(p => p.Y)), z);
                for (int j = 0; j < polygon.Length; j++)
                {
                    var a = polygon[j];
                    var next = polygon[(j + 1) % polygon.Length];
                    var edge = Edge.Between(a, next);
                    if (!edges.TryGetValue(edge, out var sides))
                        edges.Add(edge, sides = new(2));
                    sides.Add(new(a, next, z));
                    var first = Vertex(a, z);
                    var second = Vertex(next, z);
                    triangles.Add(rear ? new(center, second, first) : new(center, first, second));
                }
            }
        }
        return edges;
    }

    private static List<Wall> JoinFaces(Dictionary<Edge, List<Side>> front, Dictionary<Edge, List<Side>> rear)
    {
        var rearRim = rear.Where(e => e.Value.Count == 1).ToDictionary(e => e.Key, e => e.Value[0].Z);
        var walls = new List<Wall>();
        foreach (var (edge, sides) in front)
        {
            Profile.Require(sides.Count <= 2, "The front face has overlapping bands.");
            var top = sides.MaxBy(side => side.Z);
            double bottom;
            if (sides.Count == 2)
                bottom = sides.Min(side => side.Z);
            else if (!rearRim.Remove(edge, out bottom))
                throw new InvalidDataException("The front and rear outlines do not match.");
            if (top.Z != bottom)
                walls.Add(new(top.A, top.B, bottom, top.Z));
        }
        Profile.Require(rearRim.Count == 0, "The front and rear outlines do not match.");
        foreach (var sides in rear.Values)
        {
            Profile.Require(sides.Count <= 2, "The rear face has overlapping bands.");
            if (sides.Count != 2 || sides[0].Z == sides[1].Z)
                continue;
            var bottom = sides.MinBy(side => side.Z);
            walls.Add(new(bottom.A, bottom.B, bottom.Z, sides.Max(side => side.Z)));
        }
        return walls;
    }

    private static void TriangulateWalls(List<Wall> walls, List<Triangle> triangles)
    {
        var levels = new Dictionary<Point2, SortedSet<double>>();
        foreach (var wall in walls)
        foreach (var end in new[] { wall.A, wall.B })
        {
            if (!levels.TryGetValue(end, out var heights))
                levels.Add(end, heights = []);
            heights.Add(wall.Bottom);
            heights.Add(wall.Top);
        }
        foreach (var (a, b, bottom, top) in walls)
        {
            var aSplits = levels[a].Reverse().Where(z => bottom < z && z < top).Select(z => Vertex(a, z)).ToArray();
            var bSplits = levels[b].Where(z => bottom < z && z < top).Select(z => Vertex(b, z)).ToArray();
            var aBottom = Vertex(a, bottom);
            var bBottom = Vertex(b, bottom);
            var aTop = Vertex(a, top);
            var bTop = Vertex(b, top);
            if (aSplits.Length + bSplits.Length == 0)
            {
                triangles.Add(new(aBottom, bBottom, bTop));
                triangles.Add(new(aBottom, bTop, aTop));
                continue;
            }
            Vector3[] polygon = [aBottom, bBottom, .. bSplits, bTop, aTop, .. aSplits];
            var center = (aBottom + bTop) / 2;
            for (int i = 0; i < polygon.Length; i++)
                triangles.Add(new(center, polygon[i], polygon[(i + 1) % polygon.Length]));
        }
    }

    private static Vector3 Vertex(Point2 p, double z) => new((float)p.X, (float)p.Y, (float)z);

    private static void ValidateSolid(IReadOnlyList<Triangle> triangles)
    {
        Profile.Require(triangles.Count is > 0 and <= 700_000, "Simplify the model recipe.");
        var edges = new Dictionary<(Vector3, Vector3), int>();
        var joined = Enumerable.Range(0, triangles.Count).ToArray();
        double volume = 0;
        for (int index = 0; index < triangles.Count; index++)
        {
            var triangle = triangles[index];
            var cross = triangle.Cross;
            Profile.Require(float.IsFinite(cross.LengthSquared()) && cross.LengthSquared() > 0,
                "The model contains a collapsed triangle.");
            volume += Vector3.Dot(triangle.A, cross) / 6d;
            AddEdge(triangle.A, triangle.B, index);
            AddEdge(triangle.B, triangle.C, index);
            AddEdge(triangle.C, triangle.A, index);
        }
        Profile.Require(volume > 0 && edges.Values.All(i => i == -1) &&
            Enumerable.Range(0, triangles.Count).All(index => Root(index) == Root(0)),
            "The model must form one closed solid with outward-facing triangles.");

        void AddEdge(Vector3 a, Vector3 b, int index)
        {
            Profile.Require(!edges.ContainsKey((a, b)) && edges.GetValueOrDefault((b, a), -2) != -1,
                "The model has overlapping triangles or inconsistent winding.");
            if (edges.Remove((b, a), out int neighbor))
            {
                joined[Root(neighbor)] = Root(index);
                edges[(a, b)] = -1;
            }
            else
            {
                edges.Add((a, b), index);
            }
        }

        int Root(int index)
        {
            while (joined[index] != index)
            {
                joined[index] = joined[joined[index]];
                index = joined[index];
            }
            return index;
        }
    }
}
