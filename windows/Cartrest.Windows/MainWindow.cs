using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Cartrest.Core;
using Microsoft.Win32;
using SkiaSharp;

namespace Cartrest.Windows;

internal sealed partial class MainWindow : Window
{
    private const string ImageFilter = "Image files (*.png;*.jpg;*.jpeg;*.webp;*.bmp;*.gif)|*.png;*.jpg;*.jpeg;*.webp;*.bmp;*.gif|All files (*.*)|*.*";
    private static readonly string ResourcesDirectory = Path.Combine(AppContext.BaseDirectory, "Resources");
    private readonly string profilesDirectory;
    private readonly LabelCatalog catalog;
    private readonly List<Workspace> workspaces = [];
    private readonly WrapPanel tabs = new() { Margin = new Thickness(17, 0, 14, 0) };
    private readonly Grid proof = new() { ClipToBounds = true };
    private readonly ProofBoard mat = new();
    private readonly OrbitView orbit = new() { Visibility = Visibility.Collapsed };
    private readonly StackPanel tools = new();
    private readonly StackPanel exportBar = new() { Margin = new Thickness(0, 9, 0, 3) };
    private readonly ScrollViewer scroll;
    private readonly StackPanel viewSelector = new() { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
    private readonly WrapPanel modes = new() { HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 0, 0, 9) };
    private readonly TextBlock measurement = Ui.Label("", 14, Ui.Accent, true);
    private readonly TextBlock measureDetail = Ui.Label("", 12, Ui.Secondary);
    private readonly TextBlock status = Ui.Label("", 12, Ui.Secondary);
    private readonly StackPanel pages = new() { Orientation = Orientation.Horizontal, Margin = new Thickness(9, 0, 0, 0) };
    private readonly TextBlock pageLabel = Ui.Label("", 12);
    private readonly Button previousPage;
    private readonly Button nextPage;
    private readonly DispatcherTimer refresh;
    private readonly List<Button> pngActions = [];
    private Button? pdfAction;
    private Button? sheetAction;
    private Workspace current = null!;
    private bool designer;
    private bool disposed;
    private RatingSystem? ratingSystem;
    private MarkRole markRole;

    public MainWindow(string? profileDirectory = null)
    {
        profilesDirectory = profileDirectory ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Cartrest", "Consoles");
        Title = "Cartrest";
        Width = 1280;
        Height = 850;
        MinWidth = 850;
        MinHeight = 570;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = Ui.Window;
        FontFamily = new FontFamily("Segoe UI");
        Foreground = Ui.Text;
        UseLayoutRounding = true;
        SnapsToDevicePixels = true;
        TextOptions.SetTextFormattingMode(this, TextFormattingMode.Display);
        Icon = IconFromExecutable();
        catalog = new LabelCatalog(Path.Combine(ResourcesDirectory, "Labels"));
        refresh = new DispatcherTimer(DispatcherPriority.Background) { Interval = TimeSpan.FromMilliseconds(65) };
        refresh.Tick += (_, _) =>
        {
            refresh.Stop();
            Run(UpdateProof);
        };

        var host = new Grid { Background = Ui.Window };
        host.RowDefinitions.Add(new() { Height = GridLength.Auto });
        host.RowDefinitions.Add(new() { Height = new GridLength(1, GridUnitType.Star) });
        host.RowDefinitions.Add(new() { Height = GridLength.Auto });
        host.Children.Add(new Border { Child = Header(), BorderThickness = new Thickness(0, 0, 0, 1), BorderBrush = Ui.Edge });

        var workspaceGrid = new Grid { Margin = new Thickness(14, 13, 14, 10) };
        workspaceGrid.ColumnDefinitions.Add(new() { Width = new(1, GridUnitType.Star) });
        workspaceGrid.ColumnDefinitions.Add(new() { Width = new(350) });
        workspaceGrid.Children.Add(proof);
        Grid.SetRow(workspaceGrid, 1);
        host.Children.Add(workspaceGrid);
        proof.Children.Add(mat);
        proof.Children.Add(orbit);
        proof.Children.Add(Meter());

        var inspector = new DockPanel { Margin = new Thickness(10, 11, 10, 4) };
        var topTools = new StackPanel();
        topTools.Children.Add(viewSelector);
        topTools.Children.Add(modes);
        DockPanel.SetDock(topTools, Dock.Top);
        inspector.Children.Add(topTools);
        DockPanel.SetDock(exportBar, Dock.Bottom);
        inspector.Children.Add(exportBar);
        scroll = new ScrollViewer
        {
            Content = tools,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Padding = new Thickness(0, 0, 3, 0)
        };
        scroll.Resources[typeof(ScrollBar)] = Ui.ScrollbarStyle();
        inspector.Children.Add(scroll);
        var inspectorFrame = new Border
        {
            Margin = new Thickness(10, 0, 0, 0), Child = inspector, Background = Ui.Panel,
            BorderBrush = Ui.Edge, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(11)
        };
        Grid.SetColumn(inspectorFrame, 1);
        workspaceGrid.Children.Add(inspectorFrame);

        previousPage = Ui.Button("‹", () => SetPage(current.Page - 1));
        nextPage = Ui.Button("›", () => SetPage(current.Page + 1));
        AutomationProperties.SetName(previousPage, "Previous A4 page");
        AutomationProperties.SetName(nextPage, "Next A4 page");
        pageLabel.VerticalAlignment = VerticalAlignment.Center;
        pageLabel.Margin = new Thickness(0, 0, 6, 0);
        pages.Children.Add(previousPage);
        pages.Children.Add(pageLabel);
        pages.Children.Add(nextPage);
        status.Margin = new Thickness(17, 0, 17, 9);
        AutomationProperties.SetLiveSetting(status, AutomationLiveSetting.Polite);
        Grid.SetRow(status, 2);
        host.Children.Add(status);
        Content = host;

        PreviewKeyDown += KeyboardShortcuts;
        Closed += (_, _) => DisposeWorkspace();
        LoadProfiles();
        Select(workspaces[0]);
    }

    private System.Windows.Controls.Panel Header()
    {
        var header = new DockPanel { MinHeight = 70, LastChildFill = true, Background = Ui.Panel };
        var icon = new Image { Width = 34, Height = 34, Source = Icon, Margin = new Thickness(0, 0, 10, 0) };
        var brand = Ui.Label("Cartrest", 21, Ui.Text, true);
        brand.VerticalAlignment = VerticalAlignment.Center;
        var brandRow = Ui.Row(icon, brand);
        brandRow.Margin = new Thickness(18, 0, 0, 0);
        DockPanel.SetDock(brandRow, Dock.Left);
        header.Children.Add(brandRow);
        var import = Ui.Button("Import profile…", ImportProfile);
        import.Margin = new Thickness(10, 0, 17, 0);
        import.VerticalAlignment = VerticalAlignment.Center;
        DockPanel.SetDock(import, Dock.Right);
        header.Children.Add(import);
        tabs.VerticalAlignment = VerticalAlignment.Center;
        header.Children.Add(tabs);
        return header;
    }

    private UIElement Meter()
    {
        var lights = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        lights.Children.Add(measurement);
        lights.Children.Add(measureDetail);
        var meter = new Border
        {
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Bottom,
            Padding = new Thickness(16, 8, 12, 9),
            Margin = new Thickness(0, 0, 0, 22),
            CornerRadius = new CornerRadius(10),
            BorderThickness = new Thickness(1),
            BorderBrush = Ui.Brush("#536D60"),
            Background = Ui.Brush("#E9182520"),
            Child = Ui.Row(lights, pages)
        };
        return meter;
    }

    private static BitmapSource IconFromExecutable()
    {
        var frame = BitmapFrame.Create(new Uri("pack://application:,,,/Resources/Cartrest.ico", UriKind.Absolute),
            BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
        return frame;
    }

    private void LoadProfiles()
    {
        foreach (string path in Directory.EnumerateFiles(Path.Combine(ResourcesDirectory, "Consoles"), "*.json")
            .Where(file => Path.GetFileName(file) != "profile.schema.json"))
            AddProfile(path);
        if (Directory.Exists(profilesDirectory))
        {
            foreach (string path in Directory.EnumerateFiles(profilesDirectory, "*.json"))
                Run(() => AddProfile(path));
        }
        workspaces.Sort((a, b) =>
        {
            int order = a.Profile.Order.CompareTo(b.Profile.Order);
            return order == 0 ? string.CompareOrdinal(a.Profile.Id, b.Profile.Id) : order;
        });
    }

    private Workspace PrepareProfile(string path)
    {
        var profile = Profile.Load(path);
        if (workspaces.Any(w => w.Profile.Id == profile.Id))
            throw new InvalidDataException($"A profile with the ID '{profile.Id}' is already installed.");
        return new(profile, CartridgeMesh.Build(profile), new(catalog.Template(profile.LabelTemplate ?? profile.Id)));
    }

    private void AddProfile(string path) => workspaces.Add(PrepareProfile(path));

    private void ImportProfile()
    {
        var picker = new OpenFileDialog { Title = "Import a console profile", Filter = "Console profile (*.json)|*.json" };
        if (picker.ShowDialog(this) != true)
            return;
        Run(() =>
        {
            using var input = File.OpenRead(picker.FileName);
            if (input.Length > 256 * 1024)
                throw new InvalidDataException("Choose a profile no larger than 256 KiB.");
            using var supplied = new MemoryStream();
            input.CopyTo(supplied);
            // Validate the exact bytes that will be installed, including geometry and the mesh.
            Directory.CreateDirectory(profilesDirectory);
            string candidate = Path.Combine(profilesDirectory, $".{Guid.NewGuid():N}.tmp");
            File.WriteAllBytes(candidate, supplied.ToArray());
            try
            {
                var created = PrepareProfile(candidate);
                try
                {
                    File.Move(candidate, Path.Combine(profilesDirectory, $"{created.Profile.Id}.json"));
                }
                catch
                {
                    created.Dispose();
                    throw;
                }
                workspaces.Add(created);
                Select(created);
                SetStatus($"Imported {created.Profile.Name}.");
            }
            finally
            {
                File.Delete(candidate);
            }
        });
    }

    private void Select(Workspace workspace)
    {
        current = workspace;
        orbit.Reset();
        ratingSystem = null;
        RefreshNavigation();
        RebuildInspector(resetScroll: true);
        Run(UpdateProof);
    }

    private void RefreshNavigation()
    {
        tabs.Children.Clear();
        foreach (var workspace in workspaces)
        {
            var item = Ui.Button(workspace.Profile.Name, () => Select(workspace), active: workspace == current);
            item.Padding = new Thickness(17, 8, 17, 8);
            item.Margin = new Thickness(0, 3, 6, 3);
            tabs.Children.Add(item);
        }
        RefreshWorkspaceModes();
    }

    private void ShowDesigner(bool show)
    {
        if (designer == show)
            return;
        designer = show;
        RefreshWorkspaceModes();
        RebuildInspector(resetScroll: true);
        Run(UpdateProof);
    }

    private void RefreshWorkspaceModes()
    {
        viewSelector.Children.Clear();
        var edit = Ui.Button("Coaster & Sheet", () => ShowDesigner(false), active: !designer);
        var label = Ui.Button("Label Designer", () => ShowDesigner(true), active: designer);
        edit.Margin = label.Margin = new Thickness(0, 0, 5, 8);
        viewSelector.Children.Add(edit);
        viewSelector.Children.Add(label);
        modes.Children.Clear();
        if (!designer)
        {
            foreach (var (mode, title) in new[]
            {
                (ProofMode.Coaster, "On the coaster"), (ProofMode.Cut, "Cut"), (ProofMode.Sheet, "A4 sheet"), (ProofMode.ThreeD, "3D")
            })
            {
                var button = Ui.Button(title, () => SetMode(mode), active: current.Mode == mode);
                button.FontSize = 12;
                button.Padding = new Thickness(10, 5, 10, 5);
                button.MinHeight = 28;
                modes.Children.Add(button);
            }
        }
    }

    private void SetMode(ProofMode mode)
    {
        if (current.Mode == mode && !designer)
            return;
        designer = false;
        current.Mode = mode;
        RefreshWorkspaceModes();
        RebuildInspector();
        Run(UpdateProof);
        if (mode == ProofMode.ThreeD)
            orbit.Focus();
    }

    private void SetPage(int page)
    {
        current.Page = Math.Max(0, page);
        Run(UpdateProof);
    }

    private void RebuildInspector(bool resetScroll = false)
    {
        double offset = scroll.VerticalOffset;
        tools.Children.Clear();
        exportBar.Children.Clear();
        pngActions.Clear();
        pdfAction = sheetAction = null;
        if (designer)
            BuildDesignerInspector();
        else
            BuildCoasterInspector();
        if (resetScroll)
            scroll.ScrollToTop();
        else
            scroll.ScrollToVerticalOffset(offset);
        RequestProof();
    }

    private void RequestProof()
    {
        if (disposed)
            return;
        refresh.Stop();
        refresh.Start();
    }

    private void UpdateProof()
    {
        var settings = current.Settings;
        bool trim = current.HasValidTrim;
        var count = current.Artwork.Sum(a => a.Copies);
        var layout = trim ? PrintLayout.Layout(settings, current.Artwork) : [];
        current.Page = Math.Clamp(current.Page, 0, Math.Max(0, layout.Length - 1));
        pages.Visibility = !designer && current.Mode == ProofMode.Sheet && layout.Length > 1 ? Visibility.Visible : Visibility.Collapsed;
        pageLabel.Text = $"{current.Page + 1} / {layout.Length}";
        previousPage.IsEnabled = current.Page > 0;
        nextPage.IsEnabled = current.Page + 1 < layout.Length;
        string trimSize = $"{settings.Label.Width:0.##} × {settings.Label.Height:0.##} mm";
        double scale = current.Profile.Scale(current.Width);
        var body = current.Profile.Geometry.Body;
        measurement.Text = designer ? trimSize : current.Mode switch
        {
            ProofMode.Coaster or ProofMode.ThreeD => $"{current.Width:0.##} × {body.Height * scale:0.##} × {body.Thickness * scale:0.##} mm",
            ProofMode.Cut => trimSize,
            _ => "210 × 297 mm"
        };
        measureDetail.Text = !trim ? "Check custom trim dimensions" : designer || current.Mode == ProofMode.Cut
            ? $"{settings.Bleed:0.##} mm bleed  ·  {settings.PixelWidth} × {settings.PixelHeight} px"
            : current.Mode switch
            {
                ProofMode.Sheet => $"{count} {(count == 1 ? "label" : "labels")}  ·  {layout.Length} {(layout.Length == 1 ? "page" : "pages")}",
                ProofMode.ThreeD => "Drag to rotate  ·  Scroll to zoom",
                _ => $"{current.SelectedArtwork?.Name ?? "Empty recess"}  ·  {trimSize} trim"
            };

        var raster = trim && settings.CanRasterize;
        foreach (var button in pngActions)
            button.IsEnabled = raster && (designer || current.SelectedArtwork is not null);
        if (pdfAction is not null)
            pdfAction.IsEnabled = raster && layout.Length > 0;
        if (sheetAction is not null)
            sheetAction.IsEnabled = raster && count < PrintLayout.MaxCopies && PrintLayout.PageCapacity(settings) > 0;

        bool threeD = !designer && current.Mode == ProofMode.ThreeD;
        orbit.Visibility = threeD ? Visibility.Visible : Visibility.Collapsed;
        if (threeD)
            orbit.Display(current);
        BitmapSource? image = null;
        mat.Paper = !designer && current.Mode == ProofMode.Sheet;
        if (designer && trim)
        {
            using var label = LabelRenderer.Render(current.Draft, catalog, settings, previewLimit: 860);
            image = ProofRenderer.BitmapSource(label);
        }
        else if (!designer && !threeD)
        {
            image = current.Mode switch
            {
                ProofMode.Coaster => ProofRenderer.RenderCoaster(current, current.SelectedArtwork),
                ProofMode.Cut when trim => ProofRenderer.RenderCut(settings, current.SelectedArtwork),
                ProofMode.Sheet => ProofRenderer.RenderSheet(settings, current.Artwork, layout, current.Page),
                _ => null
            };
        }
        mat.Update(current.Profile.Palette, image);
    }

    private void KeyboardShortcuts(object sender, KeyEventArgs args)
    {
        if (Keyboard.Modifiers != ModifierKeys.Control)
            return;
        switch (args.Key)
        {
            case Key.O:
                if (designer)
                    ImportBackground();
                else
                    AddImages();
                break;
            case Key.S:
                if (designer)
                    SaveDesignedPng();
                else
                    SavePng();
                break;
            default:
                return;
        }
        args.Handled = true;
    }

    private void Run(Action action)
    {
        try
        {
            action();
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidDataException or JsonException or ArgumentException)
        {
            SetStatus(error.Message, error: true);
        }
    }

    private void SetStatus(string message, bool error = false)
    {
        status.Text = message;
        status.Foreground = error ? Ui.Brush("#FFC0AF") : Ui.Secondary;
    }

    private void DisposeWorkspace()
    {
        disposed = true;
        refresh.Stop();
        foreach (var workspace in workspaces)
            workspace.Dispose();
        catalog.Dispose();
    }
}
