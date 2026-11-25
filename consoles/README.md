# Console profiles

A Cartrest tab is defined by one JSON file. The profile supplies the console name, cutting mat and shell colors, sticker dimensions, and an ordered construction recipe for the printable model. The editor builds the same solid for **3D** and **Save STL…**. Changing **Coaster width (mm)** uniformly scales the shell, every cut and recess, and the sticker outline.

| Profile | Features to use as a reference |
| --- | --- |
| [Nintendo DS](ds.json) | Four corner radii, a chamfered label, an insertion arrow, and 17 contact channels |
| [Nintendo 3DS](3ds.json) | A custom outline with a keyed tab |
| [Nintendo Switch](switch.json) | A front grip, five rounded rear slots, and side reliefs |
| [Nintendo Switch 2](switch2.json) | A rear keyway and a red shell and cutting mat |

## Create a profile

1. Copy the closest profile to a file such as `pocket-cart.json`. Give it a unique `id` that matches the filename, and choose a display `name`. Keep `schemaVersion` at `1`.
2. Choose nominal body dimensions in millimeters and a `widthRange` that includes the nominal width. Set the front recess and the sticker outline, allowing clearance for the sticker and its chamfer or corners.
3. Update the `instructions` to match the shell. Add or remove rear features as needed. Each arrow or grip needs a matching geometry entry and instruction.
4. Set the palette. Use `#RRGGBB` colors for the mat gradient, grid, shell gradient, 3D plastic, and 2D recess. Remove `sampleArtwork` and `artworkFilePrefix` when they belong to the profile you copied.
5. In Cartrest, choose **File → Import Console Profile…** or the toolbar **+**, then select your JSON. The app checks the geometry, builds the solid, opens a tab, and installs a copy in `~/Library/Application Support/Cartrest/Consoles/`. For an installed profile, you can edit the copy in that folder and restart Cartrest to load your changes.
6. Orbit the model in **3D** to inspect both faces. Save an STL at the nominal width and again at a different width. Check the dimensions and contact details in a slicer, then export a label and check that its cut fits the recess. Print a fit test when checking real printer and vinyl tolerances.

To share a profile, submit its JSON in this directory with a short description and the sources for its proportions and details. Include the dimensions you checked and a reference photo or 3D screenshot in the pull request. The build discovers new profile files in this directory, and users can also import the same file in an installed copy of Cartrest.

## Fields

| Field | Meaning |
| --- | --- |
| `schemaVersion` | File format version. Use `1`. |
| `id` | Stable ID of up to 64 characters using lowercase ASCII letters, digits, and single internal hyphens. Variations need distinct IDs. |
| `name`, `order` | Visible name of up to 64 characters and an integer sort order. Lower numbers appear first. |
| `widthRange` | Export range with `min` and `max` in millimeters. Both are within 10–500 mm and include the nominal width. |
| `palette` | `mat.highlight`, `mat.center`, `mat.shadow`, `grid`, `shell.highlight`, `shell.shadow`, `plastic`, and `recess`. |
| `geometry` | Nominal body, recess, sticker, and optional front details. |
| `instructions` | Operations interpreted in order to build a printable extrusion with front and rear cuts. |
| `sampleArtwork` | Optional filename of an image already bundled with Cartrest. |
| `artworkFilePrefix` | Optional default filename prefix for label exports. The usual prefix is `cartrest-<id>`. |

Set `"$schema": "./profile.schema.json"` to enable field completion and validation in a JSON Schema-aware editor. Cartrest additionally checks cross-field constraints such as overlap, fit, depth, and STL closure. [JSON Schema](profile.schema.json)

### Geometry

All coordinates and lengths use millimeters. On the front face, the origin is the top-left corner of the body. X increases to the right and Y down toward the insertion edge. Keep those same coordinates for rear features, as if looking through the front face. The STL flips Y and places the uncut back face at Z = 0.

| Geometry field | Parameters |
| --- | --- |
| `unit` | `"mm"`. |
| `body` | `width`, `height`, `thickness`, and `cornerRadii` with `topLeft`, `topRight`, `bottomRight`, and `bottomLeft`. Set square corners to zero. |
| `body.vertices` | Optional array of 3–256 `{"x": …, "y": …}` points along the perimeter. The array replaces the rounded rectangle. Use vertices that reach all four declared bounds, keep crossings out of the outline, leave the closing point implicit, and ensure every horizontal slice has a single continuous span. |
| `recess` | `x`, `y`, `width`, `height`, `radius`, `chamfer`, and `depth`. The chamfer replaces the bottom-left rounded corner when positive. |
| `label` | `x`, `y`, `width`, `height`, `radius`, and `chamfer`. The entire outline must fit inside the recess. This is the vinyl cut. Bleed is set separately in the editor. |
| `arrow` | Optional triangular indentation with `centerX`, `top`, `width`, `height`, and `depth`. |
| `grip` | Optional front indentation using the same fields as `recess`. |

Work in millimeters at the intended coaster size as you author the profile. For example, a body that is 100 mm wide and 6 mm thick becomes 80 mm wide and 4.8 mm thick at an 80 mm export width. Every radius, depth, channel, and sticker measurement uses the same factor.

### Construction instructions

Start with exactly one `extrudeBody` and include exactly one `recessLabel`. The version 1 recipe supports these operations.

| `op` | Action and inputs |
| --- | --- |
| `extrudeBody` | Extrudes the `geometry.body` outline to its declared thickness. |
| `recessLabel` | Cuts `geometry.recess` into the front face. |
| `engraveArrow` | Cuts the triangle specified by `geometry.arrow` into the front face. |
| `recessGrip` | Cuts `geometry.grip` into the front face. |
| `rearChannels` | Cuts a row of open rectangular channels from `y` to the insertion edge. Set the leftmost `x`, `count`, `width`, `pitch` between channel starts, and `depth`. |
| `rearSlot` | Cuts a single slot from `y` to the insertion edge. Supply `x`, `y`, `width`, the upper-corner `radius`, and `depth`. |
| `rearRecess` | Cuts a rounded or chamfered rectangle into the back for a keyway or side relief. Supply the same fields as `geometry.recess`. |

For a shell with a label recess and ten open contact channels, a recipe can look like this.

```json
[
  { "op": "extrudeBody" },
  { "op": "recessLabel" },
  { "op": "rearChannels", "x": 11, "y": 105, "count": 10, "width": 4, "pitch": 7, "depth": 1.2 }
]
```

These cuts require a body wide enough to contain the row and tall enough for the channels to open on a straight insertion edge. Keep optional front cuts separate from the label recess, and keep same-face cuts within the outline and clear of one another. Leave a continuous layer of plastic under the deepest front cut and above the deepest rear cut. Version 1 supports up to 67 instructions and 64 individual rear cuts.

The recipe describes an extruded shell with fixed-depth cuts. For a new type of feature, extend the recipe format and its Swift and Python interpreters together. [Swift model builder](../macOS/Cartrest/CartridgeModel.swift) · [Python generator](../model/generate_models.py)

## Generate from a terminal

Run from the repository root with Python 3. The generator takes the same profile and produces a binary STL, a fit-test STL, and the scaled geometry.

```sh
python3 model/generate_models.py --profile ./pocket-cart.json --width 85 --output dist/pocket-cart
```

Omit `--width` for the nominal dimensions. To regenerate an included model, use its ID with `--console`.

```sh
python3 model/generate_models.py --console switch2 --output dist/switch2
```
