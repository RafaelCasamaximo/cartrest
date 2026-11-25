# Cartrest icon

A silver cartridge sits on a graphite background. The lifted corner shows the vinyl label. The neutral palette serves all four consoles.

| File | Use |
| --- | --- |
| [Cartrest.svg](Cartrest.svg) | Editable 1024 × 1024 vector illustration with the cutting-mat grid |
| [Cartrest.icon](Cartrest.icon) | Editable Icon Composer project with material settings and SVG artwork |
| [Cartrest-Liquid-Glass.png](Cartrest-Liquid-Glass.png) | 1024 × 1024 default appearance exported by Icon Composer |
| [layers/](layers/) | Flat SVG layers on the same 1024 × 1024 canvas, ordered from back to front |

Open `Cartrest.icon` in Icon Composer to adjust the glass, light, and appearance settings. To start from the layer files, import them in numerical order and set the background in Icon Composer. The layer artwork leaves masking and glass effects to the app. [Apple's Icon Composer guide](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)

The Details, Label surface, and Cartridge shell groups keep their own glass settings. The Dark appearance gives the lifted corner an opaque material, so the fold stays visible against the label.

The command-line build uses a static `.icns` made from the Icon Composer export for macOS 14 and later. Default, Dark, and Mono appearances are available in the editable project. An Xcode app icon target can compile them for system appearance changes.
