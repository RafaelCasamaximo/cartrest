# Cartridge label artwork

The designer catalog stores one PNG per selectable mark. Each entry in [catalog.json](catalog.json) gives the source page for the asset. The marks retain their original wording and proportions. Cropping and transparency preparation allow them to sit over the background layer.

## Use the designer

1. Choose a console and set the coaster width, bleed, and resolution in **Coaster & Sheet**. Switch to **Label Designer** at the top of the inspector.
2. In **Artwork**, import an image or pick a backing color. Choose **Fill** to cover the bleed or **Fit** to keep the whole image visible between the header and footer. Adjust zoom, framing, and an optional title.
3. In **Effects**, adjust **Noise amount** and **Grain size**, or add a **CMYK** or **Monochrome** halftone. Set **Dot spacing** in millimeters and use **Screen angle** to rotate the dot pattern. Both effects can run together. They apply to the background layer, with the title, masthead, footer, and marks composed above it.
4. In **Header & Code**, choose the layout and a **Shadow**, **Flat**, or **Hidden** header. Set the band color, band height, and logo size. Enter a front-label code to show a footer and choose **Left**, **Center**, or **Right** alignment. The field hint shows the template's code format.
5. In **Marks**, select the rating system and category. Publisher, studio, and seal each have their own position, size, and backing. Import a transparent PNG to use a graphic outside the catalog.
6. Choose **Add to Sheet** to place the finished design on the A4 layout. **Save PNG…** exports the full rectangle with bleed and resolution metadata. Each console retains its current editable draft for the session.

The A4 PDF derives its vector cut from the console profile. To compose a set, add each design to the sheet, then reopen the designer and edit the next one.

## Add a reference asset

1. Find a published asset or a clear retail front that shows the mark. Record the source URL, revision or region when known, and the mark's identity.
2. Crop to the mark and preserve its aspect ratio. Store it in `assets/` as an sRGB PNG with a lowercase hyphenated filename. Use transparency for an open background.
3. Add a mark to the catalog with a globally unique `id`, an English menu `name`, the `file`, and a `source` URL. Ratings belong in the system's `marks` array. Company logos and seals have their own lists.
4. Rebuild the app and open the designer. Check the PNG on light and dark backgrounds, then export a full-size proof. The catalog loader checks that every referenced image can be decoded.

## Define header geometry

Templates set the masthead, optional `headerOnDark` artwork, header style and colors, proportional band heights, default mark row, and code hint. Set `codeAlignment` to `left`, `center`, or `right` for the initial footer alignment. A template without this field starts centered. Set `codeTypeface` to `ocr-b` for the bundled DS typeface or use the default monospaced font. [OCR-B credits](fonts/NOTICE.md)

Use `headerLayout` to share a named entry from `headerLayouts`. `logoCenter` gives an `x` fraction of the trim width and a `y` fraction of the band height. `logoWidth` and `logoHeight` give the maximum proportion of each dimension to fit the artwork. An optional `seam` describes the lower edge from left to right. Each segment declares its `end` point and may add two cubic `controls`. Start at `x = 0`, finish at `x = 1`, and keep point coordinates within `0...1`. A layout without `seam` has a straight lower edge.

Set `labelTemplate` in a console profile to the ID of a bundled template. Choose **Custom** for user-supplied imagery and marks. [Console profile authoring](../../consoles/README.md) · [Research and sources](../../docs/cartridge-label-references.md)

The marks are credited to their respective organizations. Refer to the individual source pages for the artwork and the underlying retail photographs.
