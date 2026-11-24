---
name: Cartrest
description: "A native label editor with a cutting mat measured in millimeters."
colors:
  window-light: "#F4F5F0"
  window-dark: "#18211F"
  inspector-light: "#EAF0E9"
  inspector-dark: "#202B27"
  footer-light: "#E3EBE3"
  footer-dark: "#26332E"
  selection-light: "#D4E8D9"
  selection-dark: "#31493E"
  selection-border-light: "#82A995"
  selection-border-dark: "#5B856E"
  divider-light: "#C4D3C9"
  divider-dark: "#3B4D45"
  accent-light: "#24664B"
  accent-dark: "#29734F"
  accent-text-light: "#2A593F"
  accent-text-dark: "#BBDBBF"
  mat-highlight: "rgb(10.5% 24% 19%)"
  mat-center: "rgb(7.5% 20% 16%)"
  mat-shadow: "rgb(4.9% 15% 13%)"
  grid-and-dimensions: "rgb(68% 82% 74%)"
  graphite-highlight: "rgb(32% 36% 37%)"
  graphite-shadow: "rgb(13% 17% 19%)"
  display-highlight: "rgb(83% 88% 70%)"
  display-shadow: "rgb(64% 73% 50%)"
  display-ink: "rgb(11% 19% 10%)"
typography:
  measurement:
    fontFamily: "SF Mono"
    fontSize: "15pt"
    fontWeight: 600
  measurement-label:
    fontFamily: "SF Pro"
    fontSize: "11pt"
    fontWeight: 500
rounded:
  display-housing: "17pt"
  display-screen: "9pt"
  artwork-row: "8pt"
  thumbnail: "6pt"
spacing:
  inspector-inset: "17pt"
  footer-inset: "16pt"
  display-bottom-margin: "24pt"
components:
  measurement-display:
    rounded: "{rounded.display-housing}"
    height: "72pt"
    padding: "10pt 12pt"
  artwork-row:
    rounded: "{rounded.artwork-row}"
    padding: "6pt"
  thumbnail:
    rounded: "{rounded.thumbnail}"
    size: "38pt"
---

# Cartrest design

## Overview

The cutting mat fills the left pane. The cartridge carries the artwork, and a floating display shows the physical dimensions. The right inspector contains preview modes, the artwork list, framing and print controls, and export actions in its footer.

## Colors

`CartrestTheme` follows macOS light and dark appearance. Green highlights the artwork selection, key readings, and the PDF export action. The window, inspector, and footer use distinct surface tones with 1 pt dividers. Body text uses macOS semantic colors.

The mat uses a diagonal green gradient in both appearances. The cartridge has a graphite finish, the A4 sheet is white, and the measurement display uses dark lettering on a pale green screen.

## Typography

The display uses monospaced figures for measurements. Inspector headings, subtitles, and captions use the SwiftUI `headline`, `subheadline`, and `caption` styles. Totals use tabular figures.

## Layout

The `HSplitView` divider can be adjusted. The window opens at 1180 × 790 pt, with a minimum size of 800 × 610 pt. The left preview is at least 470 pt wide, and the right inspector ranges from 320 to 420 pt. The display floats 24 pt above the bottom of the mat. The artwork drawing area reserves clearance for the display, and the inspector scrolls above the export footer.

## Elevation & Depth

Surface tones distinguish the inspector sections. Shadows lift the cartridge and sheet off the mat. The cartridge recess darkens the graphite surface. The measurement display has a shaded housing, a recessed screen, and visible screws.

## Components

- **Preview.** The canvas uses a 5 mm and 20 mm grid in the coaster and cut views. Strokes are 0.65 pt at 10% and 17% opacity. The grid scales with the drawing and omits intervals below 3 pt. The A4 view includes a 50 mm ruler. The front artwork and the rear contact channels are visible as the cartridge rotates in 3D.
- **Measurement display.** Readings cover the coaster, cut size, and artwork size including bleed.
- **Controls.** The segmented picker switches between **On the coaster**, **Cut**, **A4 sheet**, and **3D**. The inspector uses native sliders, number fields, menus, and steppers. PDF export uses a tinted `borderedProminent` button, and PNG export uses a standard button.
- **Artwork.** The selected row has a tinted fill and outline. Each image has a square thumbnail and a single-line name.
