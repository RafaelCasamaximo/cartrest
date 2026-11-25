using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
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
    private enum DesignerPane { Artwork, Effects, HeaderAndCode, Marks }

    private const string ImageFilter = "Image files (*.png;*.jpg;*.jpeg;*.webp;*.bmp;*.gif)|*.png;*.jpg;*.jpeg;*.webp;*.bmp;*.gif|All files (*.*)|*.*";
    private static readonly string ResourcesDirectory = Path.Combine(AppContext.BaseDirectory, "Resources");
    private readonly string profilesDirectory;
    private readonly LabelCatalog catalog;
    private readonly List<Workspace> workspaces = [];
    private readonly SegmentBar<Workspace> tabs;
    private readonly SegmentBar<bool> viewSelector;
    private readonly SegmentBar<ProofMode> proofModes;
    private readonly SegmentBar<DesignerPane> designerModes;
    private readonly Grid proof = new() { ClipToBounds = true };
    private readonly ProofBoard mat = new();
    private readonly OrbitView orbit = new() { Visibility = Visibility.Collapsed };
    private readonly StackPanel tools = new();
    private readonly StackPanel exportBar = new();
    private readonly ScrollViewer scroll;
    private readonly MeasurementDisplay display = new();
    private readonly TextBlock printSummary = Ui.Label("", 12, Ui.AccentText, true);
    private readonly TextBlock pixelSummary = Ui.Label("", 12, Ui.Secondary);
    private readonly TextBlock status = Ui.Label("", 12, Ui.Secondary);
    private readonly Image toolbarMark = new()
    {
        Width = 27, Height = 27, Stretch = Stretch.Uniform, Margin = new Thickness(0, 0, 9, 0),
        VerticalAlignment = VerticalAlignment.Center, IsHitTestVisible = false
    };
    private readonly StackPanel pages = new()
    {
        Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center,
        VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 0, 0, 90)
    };
    private readonly TextBlock pageLabel = Ui.Label("", 12);
    private readonly Button previousPage;
    private readonly Button nextPage;
    private readonly DispatcherTimer refresh;
    private readonly List<Button> pngActions = [];
    private Button? pdfAction;
    private Button? sheetAction;
    private Workspace current = null!;
    private bool designer;
    private DesignerPane designerPane;
    private bool disposed;
    private RatingSystem? ratingSystem;
    private MarkRole markRole;

    public MainWindow(string? profileDirectory = null)
    {
        profilesDirectory = profileDirectory ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Cartrest", "Consoles");
        Title = "Cartrest";
        Width = 1180;
        Height = 790;
        MinWidth = 850;
        MinHeight = 600;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = Ui.Window;
        FontFamily = new FontFamily("Segoe UI");
        Foreground = Ui.Text;
        UseLayoutRounding = true;
        SnapsToDevicePixels = true;
        TextOptions.SetTextFormattingMode(this, TextFormattingMode.Display);
        Icon = LoadImage("Cartrest.ico");
        toolbarMark.Source = LoadImage("Cartrest-Mark.png");
        RenderOptions.SetBitmapScalingMode(toolbarMark, BitmapScalingMode.HighQuality);
        tabs = new SegmentBar<Workspace>("Console workspaces", w => w.Profile.Name, Select, console: true);
        viewSelector = new SegmentBar<bool>("Workspace", value => value ? "Label Designer" : "Coaster & Sheet", ShowDesigner)
        {
            HorizontalAlignment = HorizontalAlignment.Center
        };
        viewSelector.Load([false, true], false);
        proofModes = new SegmentBar<ProofMode>("Preview mode", ProofCaption, SetMode, expanded: true);
        proofModes.Load(Enum.GetValues<ProofMode>(), ProofMode.Coaster);
        designerModes = new SegmentBar<DesignerPane>("Label Designer section", DesignerCaption, SetDesignerPane, expanded: true);
        designerModes.Load(Enum.GetValues<DesignerPane>(), DesignerPane.Artwork);
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
        host.Children.Add(new Border { Child = Header(), BorderThickness = new Thickness(0, 0, 0, 1), BorderBrush = Ui.Edge });

        var workspaceGrid = new Grid();
        workspaceGrid.ColumnDefinitions.Add(new() { Width = new(1, GridUnitType.Star), MinWidth = 420 });
        workspaceGrid.ColumnDefinitions.Add(new() { Width = new(373), MinWidth = 334, MaxWidth = 465 });
        Grid.SetRow(workspaceGrid, 1);
        host.Children.Add(workspaceGrid);

        proof.Children.Add(mat);
        proof.Children.Add(orbit);
        proof.Children.Add(display);
        proof.Children.Add(pages);
        workspaceGrid.Children.Add(proof);

        var inspector = new DockPanel { Background = Ui.Panel };
        var topTools = new StackPanel();
        topTools.Children.Add(InspectorStrip(viewSelector, 10));
        var secondaryModes = new Grid();
        secondaryModes.Children.Add(proofModes);
        secondaryModes.Children.Add(designerModes);
        topTools.Children.Add(InspectorStrip(secondaryModes, 10));
        DockPanel.SetDock(topTools, Dock.Top);
        inspector.Children.Add(topTools);

        var footer = new StackPanel();
        Ui.Add(footer, printSummary, 4);
        Ui.Add(footer, pixelSummary, 8);
        Ui.Add(footer, exportBar, 0);
        status.Visibility = Visibility.Collapsed;
        status.Margin = new Thickness(0, 7, 0, 0);
        AutomationProperties.SetLiveSetting(status, AutomationLiveSetting.Polite);
        footer.Children.Add(status);
        var footerFrame = new Border
        {
            Child = footer, Background = Appearance.Brush("Footer"),
            BorderBrush = Ui.Edge, BorderThickness = new Thickness(0, 1, 0, 0),
            Padding = new Thickness(15, 10, 14, 10)
        };
        DockPanel.SetDock(footerFrame, Dock.Bottom);
        inspector.Children.Add(footerFrame);

        tools.Margin = new Thickness(15, 0, 12, 0);
        scroll = new ScrollViewer
        {
            Content = tools,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
        };
        scroll.Resources[typeof(ScrollBar)] = Ui.ScrollbarStyle();
        inspector.Children.Add(scroll);
        var inspectorFrame = new Border
        {
            Child = inspector, BorderBrush = Ui.Edge, BorderThickness = new Thickness(1, 0, 0, 0)
        };
        Grid.SetColumn(inspectorFrame, 1);
        workspaceGrid.Children.Add(inspectorFrame);

        var splitter = new GridSplitter
        {
            Width = 6, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Stretch,
            ResizeDirection = GridResizeDirection.Columns, ResizeBehavior = GridResizeBehavior.CurrentAndNext,
            Background = Brushes.Transparent
        };
        AutomationProperties.SetName(splitter, "Resize the inspector");
        workspaceGrid.Children.Add(splitter);

        previousPage = Ui.Button("‹", () => SetPage(current.Page - 1));
        nextPage = Ui.Button("›", () => SetPage(current.Page + 1));
        AutomationProperties.SetName(previousPage, "Previous A4 page");
        AutomationProperties.SetName(nextPage, "Next A4 page");
        pageLabel.VerticalAlignment = VerticalAlignment.Center;
        pageLabel.Margin = new Thickness(0, 0, 7, 0);
        pageLabel.Foreground = Brushes.White;
        pages.Children.Add(previousPage);
        pages.Children.Add(pageLabel);
        pages.Children.Add(nextPage);

        Content = host;

        PreviewKeyDown += KeyboardShortcuts;
        Closed += (_, _) => DisposeWorkspace();
        LoadProfiles();
        tabs.Load(workspaces, workspaces[0]);
        Select(workspaces[0]);
    }

    private Panel Header()
    {
        var header = new Grid { MinHeight = 53, Background = Appearance.Brush("Toolbar") };
        header.ColumnDefinitions.Add(new() { Width = new GridLength(145) });
        header.ColumnDefinitions.Add(new() { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new() { Width = new GridLength(145) });
        var brand = Ui.Label("Cartrest", 17, Ui.Text, true);
        brand.VerticalAlignment = VerticalAlignment.Center;
        var brandRow = Ui.Row(toolbarMark, brand);
        brandRow.Margin = new Thickness(16, 0, 0, 0);
        brandRow.VerticalAlignment = VerticalAlignment.Center;
        header.Children.Add(brandRow);

        var scroller = new ScrollViewer
        {
            Content = tabs, MaxHeight = 49, VerticalAlignment = VerticalAlignment.Center,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
            VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
            HorizontalContentAlignment = HorizontalAlignment.Center
        };
        Grid.SetColumn(scroller, 1);
        header.Children.Add(scroller);
        var import = Ui.IconButton("\uE710", "Import profile…", ImportProfile);
        import.HorizontalAlignment = HorizontalAlignment.Right;
        import.VerticalAlignment = VerticalAlignment.Center;
        import.Margin = new Thickness(0, 0, 16, 0);
        Grid.SetColumn(import, 2);
        header.Children.Add(import);
        return header;
    }

    private static Border InspectorStrip(UIElement child, double verticalPadding) => new()
    {
        Child = child, Padding = new Thickness(14, verticalPadding, 14, verticalPadding),
        BorderBrush = Ui.Edge, BorderThickness = new Thickness(0, 0, 0, 1)
    };

    private static BitmapSource LoadImage(string name) =>
        BitmapFrame.Create(new Uri($"pack://application:,,,/Resources/{name}", UriKind.Absolute),
            BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);

    private static string ProofCaption(ProofMode mode) => mode switch
    {
        ProofMode.Coaster => "On the coaster",
        ProofMode.Cut => "Cut",
        ProofMode.Sheet => "A4 sheet",
        _ => "3D"
    };

    private static string DesignerCaption(DesignerPane pane) => pane == DesignerPane.HeaderAndCode ? "Header & Code" : pane.ToString();

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
                tabs.Load(workspaces, created);
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
        tabs.Select(workspace);
        RefreshWorkspaceModes();
        RebuildInspector(resetScroll: true);
        Run(UpdateProof);
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
        viewSelector.Select(designer);
        proofModes.Visibility = designer ? Visibility.Collapsed : Visibility.Visible;
        designerModes.Visibility = designer ? Visibility.Visible : Visibility.Collapsed;
        proofModes.Select(current.Mode);
        designerModes.Select(designerPane);
    }

    private void SetDesignerPane(DesignerPane value)
    {
        if (designerPane == value)
            return;
        designerPane = value;
        designerModes.Select(value);
        RebuildInspector(resetScroll: true);
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
        artworkList = null;
        artworkCount = null;
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
        if (artworkCount is not null)
            artworkCount.Text = $"{count} {(count == 1 ? "sticker" : "stickers")}";
        var layout = trim ? PrintLayout.Layout(settings, current.Artwork) : [];
        current.Page = Math.Clamp(current.Page, 0, Math.Max(0, layout.Length - 1));
        pages.Visibility = !designer && current.Mode == ProofMode.Sheet && layout.Length > 1 ? Visibility.Visible : Visibility.Collapsed;
        pageLabel.Text = $"{current.Page + 1} / {layout.Length}";
        previousPage.IsEnabled = current.Page > 0;
        nextPage.IsEnabled = current.Page + 1 < layout.Length;
        double scale = current.Profile.Scale(current.Width);
        var body = current.Profile.Geometry.Body;
        var trimSize = Dimensions(settings.Label.Width, settings.Label.Height);
        var bleedSize = Dimensions(settings.Width, settings.Height);
        if (!trim)
            display.Update(("Sticker cut", "Check trim dimensions"));
        else if (designer)
            display.Update(("Sticker cut", trimSize), ("Bleed per edge", $"{settings.Bleed:0.##} mm"));
        else if (current.Mode == ProofMode.Sheet)
            display.Update(("A4 sheet", "210 × 297 mm"), ("Labels", count.ToString()), ("Pages", layout.Length.ToString()));
        else if (current.Mode == ProofMode.ThreeD)
            display.Update(("Coaster", Dimensions(current.Width, body.Height * scale)), ("Thickness", $"{body.Thickness * scale:0.##} mm"));
        else if (current.Mode == ProofMode.Cut)
            display.Update(("Sticker cut", trimSize), ("Artwork with bleed", bleedSize));
        else
            display.Update(("Coaster", Dimensions(current.Width, body.Height * scale)), ("Sticker cut", trimSize), ("Artwork with bleed", bleedSize));

        UpdateFooter(settings, layout.Length, count, trim);
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
        bool paper = !designer && current.Mode == ProofMode.Sheet;
        if (designer && trim)
        {
            using var label = LabelRenderer.Render(current.Draft, catalog, settings, previewLimit: 860);
            image = ProofRenderer.RenderDesign(label, settings);
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
        double physicalWidth = designer ? settings.Width : current.Mode switch
        {
            ProofMode.Coaster => (body.Width + 2 * ProofRenderer.CoasterPadding) * scale,
            ProofMode.Cut => settings.Width + 2 * ProofRenderer.CutPadding,
            ProofMode.Sheet => PrintLayout.PageWidth,
            _ => current.Width
        };
        mat.Update(current.Profile.Palette, image, physicalWidth, paper, pages.Visibility == Visibility.Visible);
    }

    private static string Dimensions(double width, double height) => $"{width:0.##} × {height:0.##} mm";

    private void UpdateFooter(PrintSettings settings, int pageCount, int count, bool trim)
    {
        int capacity = trim ? PrintLayout.PageCapacity(settings) : 0;
        printSummary.Text = designer ? $"Label proof · {settings.Dpi} dpi"
            : capacity > 0
                ? $"{capacity} per sheet · {pageCount} A4 {(pageCount == 1 ? "page" : "pages")}"
                : "Artwork size exceeds A4";
        if (!trim)
            printSummary.Text = "Check the custom trim dimensions";
        else if (count > 0 && pageCount == 0 && capacity > 0 && !designer)
            printSummary.Text = "Choose up to 24 labels per export";

        pixelSummary.Text = trim && settings.CanRasterize
            ? $"{settings.PixelWidth:N0} × {settings.PixelHeight:N0} px per artwork with bleed"
            : "Adjust the print dimensions or resolution";
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
        status.Foreground = Appearance.Brush(error ? "Error" : "Secondary");
        status.Visibility = string.IsNullOrWhiteSpace(message) ? Visibility.Collapsed : Visibility.Visible;
        FrameworkElementAutomationPeer.FromElement(status)?.RaiseAutomationEvent(AutomationEvents.LiveRegionChanged);
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
