# Contributing to Cartrest

You can start with a console profile, a reproducible bug report, or a change to either desktop app. Use English in issues, pull requests, code comments, and documentation.

## Try a profile in the app

1. Download [`ds-graphite.json`](examples/profiles/ds-graphite.json) using **Download raw file** on GitHub.
2. Choose **Import profile…** on Windows or **File → Import Console Profile…** on macOS and open the JSON. The new **Nintendo DS · Graphite** tab has its own mat tint, gradient direction, and grid opacity.
3. Adjust the width and export an STL. In the stock and sample profiles, the printable outline and the rear contacts scale together. The example reuses the stock DS recipe.
4. To create your own variation, change `id`, `name`, and the palette. To build a different cartridge, follow the profile guide and validate the dimensions, cuts, and rear details at the nominal width and both supported endpoints. [Profile guide](consoles/README.md) · [JSON schema](consoles/profile.schema.json)

## Work on a platform

- The SwiftUI application and disk image tools are in [`macOS/`](macOS/). Build with `./macOS/build.sh` on a Mac.
- The WPF application, C# geometry and print engine, and NSIS setup are in [`windows/`](windows/). The [Windows guide](windows/README.md) covers build, checks, setup, and uninstall.
- Changes to shared [console profiles](consoles/) or the [label catalog](design/labels/) should be checked in both apps. Artwork and physical measurements should include a source or a description of how they were obtained. [Licensing](LICENSING.md)

Report which console profile, dimensions, artwork, and export triggered an issue. For print and fit reports, include the measured 50 mm ruler or the slicer dimensions. For UI changes, include a screenshot with the relevant controls visible.
