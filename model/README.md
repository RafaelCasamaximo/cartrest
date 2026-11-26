# Cartrest 3D models

Each model is **100 mm wide and 6 mm thick** at its default size. The front recess, arrow, and rear contact detail are part of the same solid. The editor builds its **3D** preview and proportional exports from the same console profiles as these files.

| Console | Height | Cut label | Molded details |
| --- | --- | --- | --- |
| Nintendo DS | 106.06 mm | 81.8 × 86.4 mm | 17 open rear channels |
| Nintendo 3DS | 100.29 mm | 77.35 × 81.70 mm | Upper-right tab and 17 open rear channels |
| Nintendo Switch | 145.33 mm | 84.8 × 113.6 mm | Top grip recess, five contact wells, and rear side reliefs |
| Nintendo Switch 2 | 145.33 mm | 84.8 × 113.6 mm | Switch profile with an additional rear keyway |

## Nintendo DS dimensions

The DS layout follows the proportions of an approximately 33 × 35 mm cartridge. Its channels open at the insertion edge in the direction of the arrow. The rest of the rear face provides a flat bearing surface.

| Part | Width × height | Details |
| --- | --- | --- |
| Coaster | 100 × 106.06 mm | 6 mm thick |
| Recess | 82.6 × 87.2 mm | 0.6 mm deep |
| Cut label | 81.8 × 86.4 mm | Nominal clearance of 0.4 mm per side, with a 7.5 mm bottom-left chamfer |
| Rear contact channels | 3 × 12.5 mm each | 0.9 mm deep, spaced 4 mm apart center to center |
| Fit test | 36 × 28 mm | Recess of 26 × 20 × 0.6 mm |

## Slicing on the Creality K2 SE

1. Import `cartrest-ds-100mm.stl` into Creality Print in millimeters at **100%** scale, with the label face up. The K2 SE has a 220 × 215 × 245 mm build volume and supports PLA. [Official Creality specifications](https://www.creality.com/support/k2-se).
2. With a 0.4 mm nozzle, start with the **0.20 mm Standard** preset and use your filament manufacturer's profile or **Generic PLA**. For the first print, try three walls, five top layers, four bottom layers, and 15–20% infill. Preview the bridges over the recesses. The widest Switch contact well spans 16.6 mm at the default size. The ribs and broad flat rear surface sit directly on the build plate. [Creality Print quick start guide](https://www.creality.com/help/help-creality-print-quick-start-guide).
3. Print the `cartrest-fit-test.stl` from the matching model directory to check the recess. For the DS fit test, cut a 25.2 × 19.2 mm piece of paper with 3.5 mm corner radii and a 7.5 mm lower-left chamfer. Verify the full-size paper label at 100% scale before printing the vinyl.
4. Apply the label to a clean, dry surface. Use a PLA coaster for cold or room-temperature drinks. Hot drinkware and dishwashers can deform PLA or weaken adhesion. [Creality PLA guide](https://uatstore.creality.com/blogs/basics/pla-filament-guide-properties-settings).

## Other widths

In the editor, enter the desired width under **Model dimensions** and select **Save STL…**. The same factor scales all three axes and the label outline. For example, a Switch coaster at 80 mm wide measures **80 × 116.26 × 4.8 mm** and takes a **67.84 × 90.88 mm** label.

To create a matching fit test at a custom size, run the generator with Python 3. The following example writes a 90 × 95.454 × 5.4 mm DS coaster, a fit-test STL, and dimensions for a 73.62 × 77.76 mm label to `model/90mm/`.

```sh
python3 model/generate_models.py --width 90
```

The generated `dimensions.json` records dimensions in millimeters. Label, recess, and contact-channel coordinates use the top-left corner of the front face as their origin. If you resize the template directly in a slicer, apply the same factor to X, Y, and Z and enter the corresponding width in Cartrest.

Use `--console` with `ds`, `3ds`, `switch`, or `switch2`. The following command writes a smaller Switch coaster and its dimensions to a separate directory.

```sh
python3 model/generate_models.py --console switch --width 90 --output dist/switch-90mm
```

The four built-in profiles support widths from **60 to 180 mm**. Pass `--profile /path/to/console.json` with `--output` to generate a model from a community profile. Each output directory holds the coaster, fit test, and corresponding dimensions.

## Coaster holders

Set **Coaster width** in the editor, then open **Coaster holder**. Every slot fits the current console and width. Set the slot count and the clearance per side to suit your print. The default is four slots with **0.5 mm clearance per side**. Increasing the clearance by 0.1 mm adds 0.2 mm to both interior slot dimensions.

Use **Save Holder STL…** and import the file at **100%** scale with the flat base on the build plate. The guides use a beveled opening and can print without supports in this orientation. Slide each coaster in vertically with its bottom edge first. Compare the displayed outside dimensions with the usable build area before slicing. A four-slot holder for 100 mm DS coasters measures **107.40 × 77.70 × 39.26 mm**.

For command-line export, pass `--holder-slots` to generate the holder STL. These commands reproduce the downloadable examples. [Four-slot DS STL](holders/cartrest-ds-holder-4slots-100mm.stl) · [Six-slot 3DS STL](holders/cartrest-3ds-holder-6slots-90mm.stl)

```sh
python3 model/generate_models.py --console ds --width 100 --holder-slots 4 --output dist/holders
python3 model/generate_models.py --console 3ds --width 90 --holder-slots 6 --holder-clearance 0.6 --output dist/holders
```

## Model sources

The nominal measurements and model instructions are defined in `consoles/`. Cartrest bundles those profiles and generates the STL directly. The downloadable DS files are in `model/`. The other files are in `model/3ds/`, `model/switch/`, and `model/switch2/`. [Profile authoring guide](../consoles/README.md) · [Generator](generate_models.py) · [DS dimensions](dimensions.json) · [3DS dimensions](3ds/dimensions.json) · [Switch dimensions](switch/dimensions.json) · [Switch 2 dimensions](switch2/dimensions.json)

On the face, X increases to the right and Y increases downward. To keep the chamfer and arrow oriented correctly in the STL top view, the generator flips Y. Rounded corners are approximated by short segments, and the flat base sits at Z = 0. The default 0.4 mm clearance is measured perpendicular to each boundary, including the chamfer.

To reproduce the default files and check them against the repository, generate a copy in a separate directory.

```sh
python3 model/generate_models.py --output dist/model-100mm
cmp model/dimensions.json dist/model-100mm/dimensions.json
cmp model/cartrest-ds-100mm.stl dist/model-100mm/cartrest-ds-100mm.stl
cmp model/cartrest-fit-test.stl dist/model-100mm/cartrest-fit-test.stl
```

## Shape references and alternatives

- A caliper measurement of a DS cartridge gave a width of 32.93 mm, a height of 34.96 mm, and a thickness of 3.79 mm. The same collector measured 34.90 mm across the widest part of the 3DS cartridge, which has a side tab. [Collector's measurements](https://www.reddit.com/r/gamecollecting/comments/23stkf/q_dimensions_for_game_cartridges/#:~:text=DS%3A%2034.96).
- Nintendo's drawings show the differences between the body corners. Derrick Rossignol's front photograph shows the bottom-left label chamfer and the insertion arrow at the edge. [Nintendo patent drawings](https://patents.google.com/patent/USD536382S1/en) · [Front photograph](https://commons.wikimedia.org/wiki/File:Nintendo_DS_game_card.jpg).
- Nintendo's cartridge design places parallel terminals between ribs along the insertion edge. The coaster uses a row of 17 open channels as a printable interpretation. [Nintendo cartridge patent](https://patents.google.com/patent/US20090305792A1/en) · [17-pin reference](https://www.hardwarebook.info/DS_Game_Card) · [NTR-005 rear photos](https://gameverifying.com/wiki/depository/ntr005).
- Nintendo's 3DS manual shows the tab that extends beyond the body of a 3DS game card. The 3DS coaster uses a nominal 34.9 mm overall card width for the scaled outline. [Nintendo 3DS operations manual](https://www.nintendo.com/eu/media/downloads/support_1/nintendo_3ds_14/Nintendo3DS_OperationsManual_UK.pdf) · [Collector's measurements](https://www.reddit.com/r/gamecollecting/comments/23stkf/q_dimensions_for_game_cartridges/#:~:text=DS%3A%2034.96).
- Nintendo's Switch cartridge patent describes an approximately 21.4 × 31.1 mm case and shows the five molded contact groups. The Switch 2 profile adds the rear keyway visible in Aomaf's cartridge photograph. Nintendo's support comparison distinguishes the gray Switch cards from the red Switch 2 cards. [Nintendo patent US 9,853,379](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/9853379) · [Switch 2 rear photograph](https://commons.wikimedia.org/wiki/File:Backofswitch2gamecard.jpg) · [Nintendo card comparison](https://www.nintendo.com/en-gb/Support/Nintendo-Switch-2/Differences-Between-Nintendo-Switch-2-and-Nintendo-Switch-Consoles-and-Accessories-2955851.html).
- Retroid lists its replacement labels at 27 × 28.5 mm. Those dimensions informed the scaled label. [Retroid DS labels](https://retroid.nl/game-labels/nintendo-ds/).
- **Fun Cartridge** by AF_Inventions is a paid pack that includes `FUN CARTRIDGE - DS - COASTER.STL`. A commercial license is available separately. [Cults listing](https://cults3d.com/en/3d-model/game/fun-cartridge-keychain-coasters-tray-more/makes) · [Creator's terms on Thangs](https://thangs.com/prints/designer/af_inventions/3d-model/FUN%20CARTRIDGE%20%7C%20KEYCHAIN%2C%20COASTERS%2C%20TRAY%20%26%20MORE-1541080).
- The **Nintendo DS dummy cartridge** by magu is a free 33 × 35 × 3.75 mm STL made to cover Slot-1. It is a reference for the proportions of the original cartridge. [Creator's model](https://cults3d.com/en/3d-model/gadget/nintendo-ds-dummy-cartridge-ds-dsi-3ds-2ds).

The generator checks for one closed solid with consistent face orientation after converting coordinates to STL precision. Digital checks covered the model bounds, the open contact channels, and the scaled label dimensions. Use the fit test to verify label clearance with your printer and vinyl.
