---
title: Shelf Bench app icon
description: Source and notes for the Shelf Bench macOS app icon, derived from the shelf-bridge icon.
created_by: claude-code
created: 2026-10-23T23:45:00+03:00
updated_by: claude-code
updated: 2026-10-24T00:05:00+03:00
---

# Shelf Bench app icon

`bench-app-icon-1024.svg` is the master. It keeps the shelf-bridge language: the dark squircle
(`#1A1715`) and the three stacked vermilion slabs (`#8A2A1B`, `#C2331F`, `#E8412C`). The Bench cue
is a terminal prompt under the slabs: a `>` chevron and an underscore cursor in `#F3F1EE`.

Palette: squircle `#1A1715`, slabs as above, prompt `#F3F1EE`.

## Rendering

The PNGs in `App/Resources/Assets.xcassets/AppIcon.appiconset` (16 to 1024 px) are rendered from
the SVG with a small Swift script that loads it with `NSImage` and draws it into an
`NSBitmapImageRep` at each pixel size. Re-render after any change to the SVG.
