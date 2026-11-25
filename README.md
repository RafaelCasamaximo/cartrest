<p align="center">
  <img src="docs/images/cartrest.png" width="96" height="96" alt="">
</p>

<h1 align="center">Cartrest</h1>

<p align="center">3D-printable cartridge coasters and a native macOS editor for vinyl labels.</p>

<p align="center">
  <strong><a href="https://github.com/RafaelCasamaximo/cartrest/releases/latest">Download for macOS</a></strong>
  · macOS 14 or later · Apple Silicon and Intel
</p>

![The Cartrest editor with console tabs, the Mario Kart DS cartridge label on a graphite cartridge, a floating measurement display, and editing controls on the right.](docs/images/editor.png)

Cartrest pairs four 3D-printable cartridge models with a SwiftUI editor for labels that fit their recesses. Choose **Nintendo DS**, **Nintendo 3DS**, **Nintendo Switch**, or **Nintendo Switch 2** to preview the matching model, arrange copies on an A4 sheet, and export a **full-scale PDF** with bleed, a vector cut line, and a 50 mm reference ruler.

## Install on macOS

1. Download `Cartrest-1.2.1-macOS-universal.dmg`. [GitHub Releases](https://github.com/RafaelCasamaximo/cartrest/releases/latest)
2. Open the disk image and drag **Cartrest** to **Applications**.
3. Eject the disk image and open Cartrest from Finder.

The app in this release uses ad hoc signing. To verify the download, save the DMG and its `.sha256` file in the same folder and run the following command from that folder.

```sh
shasum -a 256 -c Cartrest-1.2.1-macOS-universal.dmg.sha256
```

## Lay out a sticker sheet

1. Choose a console in the toolbar. Each tab keeps its own artwork, framing, copy counts, and print settings for the session.
2. Select **Add images…** and choose one or more images.
3. Select each image to adjust its zoom, position, and copy count. **On the coaster** shows the artwork inside the recess, and **Cut** shows its print boundary.
4. Open **A4 sheet** to check the layout and page count. The larger Switch labels fit two per A4 sheet at the default size and bleed.
5. Select **Save A4 PDF…** to print the sheet or **Save PNG…** to export the selected artwork.

Print a test on plain paper at **Actual Size (100%)**, measure the 50 mm ruler, and check the cut against the recess before printing on vinyl. White printable vinyl helps preserve artwork colors over dark gray PLA.

## Game artwork and print examples

Each console set includes four retail cartridge labels, one from each series. Open the matching tab to import the PNGs, or download the full-size A4 sheets for a 100 mm coaster. [Import-ready PNGs and sources](examples/README.md) · [Print guide](print/README.md)

| Console | Mario | Pokémon | Zelda | Kirby | A4 |
| --- | --- | --- | --- | --- | --- |
| Nintendo DS | Mario Kart DS | Pokémon Platinum Version | Phantom Hourglass | Super Star Ultra | [Cartridge labels](print/cartrest-cartridge-labels-a4.pdf) · [Box covers](print/cartrest-example-a4.pdf) |
| Nintendo 3DS | Mario Kart 7 | Pokémon X | Ocarina of Time 3D | Triple Deluxe | [Cartridge labels](print/cartrest-3ds-cartridge-labels-a4.pdf) |
| Nintendo Switch | Mario Kart 8 Deluxe | Pokémon Legends: Arceus | Tears of the Kingdom | Kirby and the Forgotten Land | [Cartridge labels](print/cartrest-switch-cartridge-labels-a4.pdf) |
| Nintendo Switch 2 | Mario Kart World | Pokémon Legends: Z-A¹ | Breath of the Wild¹ | Kirby Air Riders | [Cartridge labels](print/cartrest-switch2-cartridge-labels-a4.pdf) |

¹ Nintendo Switch 2 Edition.

| Nintendo 3DS | Nintendo Switch | Nintendo Switch 2 |
| --- | --- | --- |
| [![The 3DS workspace with the Pokémon X cartridge label.](docs/images/editor-3ds.jpg)](docs/images/editor-3ds.jpg) | [![The Switch workspace with the Tears of the Kingdom cartridge label.](docs/images/editor-switch.jpg)](docs/images/editor-switch.jpg) | [![The Switch 2 workspace with the Kirby Air Riders cartridge label.](docs/images/editor-switch2.jpg)](docs/images/editor-switch2.jpg) |

## Explore the cartridge in 3D

Select **3D** and drag to orbit the cartridge. Scroll to zoom, then choose **Recenter** to restore the starting view. Each tab previews the same solid it exports for printing, with the matching shell color and the selected artwork inside the recess. The DS examples below use the original cartridge labels.

| Pokémon Platinum Version | Kirby Super Star Ultra |
| --- | --- |
| ![3D cartridge with the Pokémon Platinum Version cartridge label.](docs/images/pokemon-platinum-3d.png) | ![3D cartridge with the Kirby Super Star Ultra cartridge label.](docs/images/kirby-super-star-ultra-3d.png) |

<p align="center">
  <img src="docs/images/cartridge-back.png" width="340" alt="Back of the cartridge, showing the 17 recessed contact channels.">
</p>

## Print the coaster

| Console | Coaster | Cut label | Files |
| --- | --- | --- | --- |
| Nintendo DS | 100 × 106.06 × 6 mm | 81.8 × 86.4 mm | [STL](model/cartrest-ds-100mm.stl) · [Fit test](model/cartrest-fit-test.stl) |
| Nintendo 3DS | 100 × 100.29 × 6 mm | 77.35 × 81.70 mm | [STL](model/3ds/cartrest-3ds-100mm.stl) · [Fit test](model/3ds/cartrest-fit-test.stl) |
| Nintendo Switch | 100 × 145.33 × 6 mm | 84.8 × 113.6 mm | [STL](model/switch/cartrest-switch-100mm.stl) · [Fit test](model/switch/cartrest-fit-test.stl) |
| Nintendo Switch 2 | 100 × 145.33 × 6 mm | 84.8 × 113.6 mm | [STL](model/switch2/cartrest-switch2-100mm.stl) · [Fit test](model/switch2/cartrest-fit-test.stl) |

For a custom size, set **Coaster width (mm)** under **Model dimensions**, then select **Save STL…**. Height, thickness, and the label cut scale with the width. Export the labels from the same tab so they fit the saved model.

Import the STL in millimeters at 100% scale, with the label face up. On the Creality K2 SE with a 0.4 mm nozzle, the 0.20 mm PLA preset is a starting point. Print the small fit test to check the recess and label clearance before committing to the full coaster. [Model and slicing guide](model/README.md)

## Add a console or a variation

1. Copy a profile such as [ds.json](consoles/ds.json) and choose a unique ID and tab name.
2. Set the cutting mat palette, cartridge dimensions, and sticker outline. Adjust the construction instructions to define the body, label recess, and rear contact details.
3. Choose **File → Import Console Profile…** or click the toolbar **+**. Inspect the result in **3D** and export a test STL before sharing the JSON or opening a pull request.

The palette can set the tint color and strength, gradient direction, grid opacity, and shell colors for each tab. [Profile authoring guide](consoles/README.md#create-a-profile) · [Palette settings](consoles/README.md#palette) · [Construction instructions](consoles/README.md#construction-instructions) · [JSON Schema](consoles/profile.schema.json)

## Build from source

Install Xcode or the Xcode Command Line Tools and run the build from the project root. It produces `Cartrest.app`.

```sh
./macOS/build.sh
```

The release packager builds a universal app and writes a DMG and SHA-256 checksum to `dist/`. It uses Python 3 with `venv` and `pip` to install the pinned packaging dependencies.

```sh
./macOS/package-release.sh
```

For distribution signing, set `CARTREST_CODESIGN_IDENTITY` to a Developer ID Application identity. Set `CARTREST_NOTARY_PROFILE` to a stored Keychain profile for `notarytool` to submit and staple the disk image. [Packaging for macOS distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)

| Path | Contents |
| --- | --- |
| `macOS/Cartrest/` | SwiftUI editor, 3D preview, geometry, and Core Graphics export |
| `macOS/Release/` | Disk image background and packaging settings |
| `consoles/` | Console profiles, construction recipes, and a contributor guide |
| `model/` | Downloadable meshes, fit tests, and the command-line generator |
| `design/icon/` | Editable SVG, Icon Composer project, and rendered icon |
| `examples/` | Original retail scans, importable artwork, and source links |
| `print/` | Full-size A4 sheets for box covers and cartridge labels |
| `docs/images/` | App screenshots |

The A4 preview uses the same placement calculations as the PDF export. The app and the command-line model generator read the same console profiles. Command-line builds bundle a static `.icns` made from the Liquid Glass export. [Icon Composer project](design/icon/Cartrest.icon) · [SVG source](design/icon/Cartrest.svg) · [Icon editing and export](design/icon/README.md) · [Design notes](DESIGN.md)

## Acknowledgments

Thanks to **AF_Inventions** for sharing *Fun Cartridge* and its Nintendo DS coaster design, and to **magu** for publishing the dummy cartridge used as a reference for the original proportions. [Fun Cartridge on Cults](https://cults3d.com/en/3d-model/game/fun-cartridge-keychain-coasters-tray-more) · [Nintendo DS dummy cartridge on Cults](https://cults3d.com/en/3d-model/gadget/nintendo-ds-dummy-cartridge-ds-dsi-3ds-2ds)

Thanks to **LaunchBox Games Database**, **VGCollect**, **No-Intro Wiki**, and the photographers who shared the retail artwork and cartridge photos used in the examples. [Sources by game](examples/README.md)
