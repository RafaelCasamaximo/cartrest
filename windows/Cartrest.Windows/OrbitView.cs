using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Media.Media3D;
using SkiaSharp;

namespace Cartrest.Windows;

internal sealed class OrbitView : Grid
{
    private readonly Model3DGroup cartridge = new();
    private readonly PerspectiveCamera camera = new() { FieldOfView = 39, LookDirection = new(0, 0, -1), UpDirection = new(0, 1, 0), NearPlaneDistance = 0.06 };
    private readonly QuaternionRotation3D rotation = new();
    private Point? dragOrigin;
    private double distance = 3.9;

    public OrbitView()
    {
        Focusable = true;
        Background = Brushes.Transparent;
        Cursor = Cursors.SizeAll;
        Margin = new Thickness(0, 0, 0, 57);
        AutomationProperties.SetName(this, "Rotatable cartridge model");
        AutomationProperties.SetHelpText(this, "Drag or use arrow keys to rotate. Scroll or use plus and minus to zoom. Home resets the view.");
        cartridge.Transform = new RotateTransform3D(rotation);
        var lights = new Model3DGroup();
        lights.Children.Add(new AmbientLight(Color.FromRgb(123, 130, 127)));
        lights.Children.Add(new DirectionalLight(Color.FromRgb(240, 240, 228), new(-0.55, -0.7, -1)));
        lights.Children.Add(new DirectionalLight(Color.FromRgb(129, 156, 163), new(0.45, 0.2, 1)));
        var view = new Viewport3D { Camera = camera, IsHitTestVisible = false, ClipToBounds = true };
        view.Children.Add(new ModelVisual3D { Content = lights });
        view.Children.Add(new ModelVisual3D { Content = cartridge });
        Children.Add(view);
        Reset();

        MouseLeftButtonDown += (_, e) =>
        {
            Focus();
            if (e.ClickCount == 2)
            {
                Reset();
                return;
            }
            dragOrigin = e.GetPosition(this);
            CaptureMouse();
            e.Handled = true;
        };
        MouseMove += (_, e) =>
        {
            if (dragOrigin is not { } origin || e.LeftButton != MouseButtonState.Pressed)
                return;
            var end = e.GetPosition(this);
            Rotate((end.X - origin.X) * 0.66, (end.Y - origin.Y) * 0.66);
            dragOrigin = end;
        };
        MouseLeftButtonUp += (_, _) => ReleaseMouseCapture();
        LostMouseCapture += (_, _) => dragOrigin = null;
        MouseWheel += (_, e) =>
        {
            Zoom(Math.Pow(0.86, e.Delta / 120d));
            e.Handled = true;
        };
        KeyDown += (_, e) =>
        {
            switch (e.Key)
            {
                case Key.Left: Rotate(-10, 0); break;
                case Key.Right: Rotate(10, 0); break;
                case Key.Up: Rotate(0, -10); break;
                case Key.Down: Rotate(0, 10); break;
                case Key.Add or Key.OemPlus: Zoom(0.86); break;
                case Key.Subtract or Key.OemMinus: Zoom(1 / 0.86); break;
                case Key.Home: Reset(); break;
                default: return;
            }
            e.Handled = true;
        };
    }

    public void Reset()
    {
        rotation.Quaternion = new Quaternion(new(0, 1, 0), -18) * new Quaternion(new(1, 0, 0), 17);
        distance = 3.9;
        camera.Position = new(0, 0, distance);
    }

    private void Rotate(double x, double y)
    {
        var next = new Quaternion(new(0, 1, 0), x) * new Quaternion(new(1, 0, 0), y) * rotation.Quaternion;
        next.Normalize();
        rotation.Quaternion = next;
    }

    private void Zoom(double factor)
    {
        distance = Math.Clamp(distance * factor, 2.2, 10);
        camera.Position = new(0, 0, distance);
    }

    public void Display(Workspace workspace)
    {
        cartridge.Children.Clear();
        var profile = workspace.Profile;
        var body = profile.Geometry.Body;
        double unit = 1.65 / Math.Max(body.Width, body.Height);
        Point3D Center(double x, double y, double z) => new((x - body.Width / 2) * unit,
            (y - body.Height / 2) * unit, (z - body.Thickness / 2) * unit);

        var shell = new MeshGeometry3D();
        var relief = new MeshGeometry3D();
        foreach (var triangle in workspace.Model.Triangles)
        {
            // Inner horizontal faces use the recessed plastic color while the wall normals catch light.
            var target = triangle.A.Z == triangle.B.Z && triangle.B.Z == triangle.C.Z && triangle.A.Z > 0 &&
                triangle.A.Z < (float)body.Thickness ? relief : shell;
            target.Positions.Add(Center(triangle.A.X, triangle.A.Y, triangle.A.Z));
            target.Positions.Add(Center(triangle.B.X, triangle.B.Y, triangle.B.Z));
            target.Positions.Add(Center(triangle.C.X, triangle.C.Y, triangle.C.Z));
        }

        AddSurface(shell, new SolidColorBrush(Ui.ColorFrom(SKColor.Parse(profile.Palette.Plastic))));
        AddSurface(relief, new SolidColorBrush(Ui.ColorFrom(SKColor.Parse(profile.Palette.Recess))));
        if (workspace.SelectedArtwork is not { } art)
            return;

        var label = profile.Geometry.Label;
        var scale = profile.Scale(workspace.Width);
        var settings = new Cartrest.Core.PrintSettings(label.Scale(scale), workspace.Bleed, Math.Min(workspace.Dpi, 160));
        if (!settings.CanRasterize)
            return;
        using var image = Cartrest.Core.PrintLayout.Rasterize(settings, art);
        var labelGeometry = new MeshGeometry3D();
        double z = body.Thickness - profile.Geometry.Recess.Depth + 0.016;
        var outline = Cartrest.Core.Outline.ForRegion(label);
        AddVertex(label.X + label.Width / 2, label.Y + label.Height / 2);
        foreach (var p in outline)
            AddVertex(p.X, p.Y);
        for (int i = 0; i < outline.Length; i++)
        {
            labelGeometry.TriangleIndices.Add(0);
            labelGeometry.TriangleIndices.Add((i + 1) % outline.Length + 1);
            labelGeometry.TriangleIndices.Add(i + 1);
        }
        var proof = ProofRenderer.BitmapSource(image);
        var texture = new ImageBrush(proof) { Stretch = Stretch.Fill };
        texture.Freeze();
        AddSurface(labelGeometry, texture);

        void AddVertex(double x, double y)
        {
            labelGeometry.Positions.Add(Center(x, body.Height - y, z));
            labelGeometry.TextureCoordinates.Add(new Point(
                ((x - label.X) * scale + settings.Bleed) / settings.Width,
                ((y - label.Y) * scale + settings.Bleed) / settings.Height));
        }
    }

    private void AddSurface(MeshGeometry3D mesh, Brush brush)
    {
        if (mesh.Positions.Count == 0)
            return;
        mesh.Freeze();
        var material = new DiffuseMaterial(brush);
        material.Freeze();
        cartridge.Children.Add(new GeometryModel3D(mesh, material));
    }

    internal Quaternion Orientation => rotation.Quaternion;
    internal void TurnForTesting() => Rotate(166, -45);
}
