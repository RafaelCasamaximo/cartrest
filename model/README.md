# Cartrest 3D model

The coaster measures **100 × 106.06 × 6 mm** (width, height, thickness). The face follows the proportions of a Nintendo DS cartridge, which measures approximately 33 × 35 mm. The front has a recessed arrow and a recess for the artwork. On the back, 17 channels open at the insertion edge indicated by the arrow. The rest of the rear face provides a flat bearing surface.

| Part | Width × height | Details |
| --- | --- | --- |
| Coaster | 100 × 106.06 mm | 6 mm thick |
| Recess | 82.6 × 87.2 mm | 0.6 mm deep |
| Cut label | 81.8 × 86.4 mm | Nominal clearance of 0.4 mm per side, with a 7.5 mm bottom-left chamfer |
| Rear contact channels | 3 × 12.5 mm each | 0.9 mm deep, spaced 4 mm apart center to center |
| Fit test | 36 × 28 mm | Recess of 26 × 20 × 0.6 mm |

## Slicing on the Creality K2 SE

1. Import `cartrest-ds-100mm.stl` into Creality Print in millimeters at **100%** scale, with the label face up. The K2 SE has a 220 × 215 × 245 mm build volume and supports PLA. [Official Creality specifications](https://www.creality.com/support/k2-se).
2. With a 0.4 mm nozzle, start with the **0.20 mm Standard** preset and use your filament manufacturer's profile or **Generic PLA**. For the first print, try three walls, five top layers, four bottom layers, and 15–20% infill. Preview the slices with supports off and check that the channel roofs bridge across the 3 mm gaps. The ribs and broad flat rear surface sit directly on the build plate. [Creality Print quick start guide](https://www.creality.com/help/help-creality-print-quick-start-guide).
3. For a quick clearance check, print `cartrest-fit-test.stl` and cut a 25.2 × 19.2 mm piece of paper with 3.5 mm radii on the three rounded corners and a 7.5 mm chamfer on the bottom-left corner. Then verify the full-size paper label at 100% scale before printing the vinyl.
4. Apply the label to a clean, dry surface. Use a PLA coaster for cold or room-temperature drinks. Hot drinkware and dishwashers can deform PLA or weaken adhesion. [Creality PLA guide](https://uatstore.creality.com/blogs/basics/pla-filament-guide-properties-settings).

## Other widths

Run the generator with Python 3 from the project root. The following example creates `model/90mm/` with a 90 × 95.454 × 6 mm coaster, a fit-test STL, and dimensions for a 73.62 × 77.76 mm label. Thickness and recess depths stay fixed.

```sh
python3 model/generate_models.py --width 90
```

The generated `dimensions.json` records dimensions in millimeters. Label, recess, and contact-channel coordinates use the top-left corner of the front face as their origin. To scale the 100 mm STL in a slicer, use the same scale factor on X and Y, set Z to 100%, and apply that XY factor to the label dimensions and corners.

Supported widths range from **60 to 180 mm**. Use one output directory per width so the coaster, fit test, and corresponding dimensions stay together. Pass `--output` to choose a directory.

## Dimensions shared with the editor

The generator's `DIMENSIONS` table defines the geometry. Running it with the defaults regenerates the two STLs and the JSON in `model/`. The app build bundles this JSON for the preview and the PDF cut outline. [Generator](generate_models.py) · [Default dimensions](dimensions.json)

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
- Retroid lists its replacement labels at 27 × 28.5 mm. Those dimensions informed the scaled label. [Retroid DS labels](https://retroid.nl/game-labels/nintendo-ds/).
- **Fun Cartridge** by AF_Inventions is a paid pack that includes `FUN CARTRIDGE - DS - COASTER.STL`. A commercial license is available separately. [Cults listing](https://cults3d.com/en/3d-model/game/fun-cartridge-keychain-coasters-tray-more/makes) · [Creator's terms on Thangs](https://thangs.com/prints/designer/af_inventions/3d-model/FUN%20CARTRIDGE%20%7C%20KEYCHAIN%2C%20COASTERS%2C%20TRAY%20%26%20MORE-1541080).
- The **Nintendo DS dummy cartridge** by magu is a free 33 × 35 × 3.75 mm STL made to cover Slot-1. It is a reference for the proportions of the original cartridge. [Creator's model](https://cults3d.com/en/3d-model/gadget/nintendo-ds-dummy-cartridge-ds-dsi-3ds-2ds).

Digital checks verified a closed mesh, 17 open mouths at the insertion edge, and solid material above the channels at widths of 60, 100, and 180 mm. Use the fit test to verify label clearance with your printer and vinyl.
