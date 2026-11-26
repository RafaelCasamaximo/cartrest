using Cartrest.Core;

namespace Cartrest.Windows;

internal enum ProofMode { Coaster, Cut, Sheet, ThreeD }

internal sealed class Workspace(Profile profile, CartridgeMesh model, LabelDraft draft) : IDisposable
{
    public Profile Profile { get; } = profile;
    public CartridgeMesh Model { get; } = model;
    public LabelDraft Draft { get; } = draft;
    public double Width { get; set; } = profile.Geometry.Body.Width;
    public int HolderSlots { get; set; } = CoasterHolder.DefaultSlots;
    public double HolderClearance { get; set; } = CoasterHolder.DefaultClearance;
    public double Bleed { get; set; } = 2;
    public int Dpi { get; set; } = 300;
    public int Selected { get; set; }
    public int Page { get; set; }
    public ProofMode Mode { get; set; }
    public bool CustomTrim { get; set; }
    public Region CustomLabel { get; set; } = profile.Geometry.Label with { X = 0, Y = 0 };
    public List<Artwork> Artwork { get; } = [];
    public Artwork? SelectedArtwork => Artwork.ElementAtOrDefault(Selected);
    public PrintSettings Settings => new(CustomTrim ? CustomLabel : Profile.LabelAt(Width), Bleed, Dpi);
    public CoasterHolder Holder => new(Profile, Width, HolderSlots, HolderClearance);

    public bool HasValidTrim
    {
        get
        {
            if (!CustomTrim)
                return true;
            var label = CustomLabel;
            double side = Math.Min(label.Width, label.Height);
            return label.Width is >= 20 and <= 160 && label.Height is >= 20 and <= 160 &&
                label.Radius >= 0 && label.Radius <= side / 2 &&
                label.Chamfer >= 0 && label.Chamfer <= side - label.Radius;
        }
    }

    public void Dispose()
    {
        Draft.Dispose();
        foreach (var artwork in Artwork)
            artwork.Bitmap.Dispose();
    }
}
